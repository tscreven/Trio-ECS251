import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

struct CalculateInput: Decodable {
    let timestamp: Double // Unix timestamp (seconds since epoch)
    let glucose: Decimal // mg/dL
}

struct Calculate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calculate",
        abstract: "Calculate insulin dosing for a given algorithm state and new glucose reading."
    )

    @Option(name: [.customShort("s"), .long], help: "Path to simulation state directory")
    var stateDir: String

    @Option(name: .shortAndLong, help: "Input file path (use '-' for STDIN)") var input: String?

    @Option(name: .shortAndLong, help: "Output file path (use '-' for STDOUT)") var output: String?

    func run() throws {
        // 1. Read and decode input
        let inputData: Data
        if let inputPath = input, inputPath != "-" {
            let url = URL(fileURLWithPath: inputPath)
            inputData = try Data(contentsOf: url)
        } else {
            inputData = FileHandle.standardInput.readDataToEndOfFile()
        }

        let calcInput = try JSONCoding.decoder.decode(CalculateInput.self, from: inputData)
        let now = Date(timeIntervalSince1970: calcInput.timestamp)
        let storage = SimulationStorage(stateDir: stateDir)

        // 2. Store glucose
        try storage.storeGlucose(at: now, glucose: calcInput.glucose)

        // 3. Regenerate profile
        let inputs = try storage.loadProfileInputs(clock: now)
        var preferences = inputs.preferences

        let model = "722"
        let profile = try ProfileGenerator.generate(
            pumpSettings: inputs.pumpSettings,
            bgTargets: inputs.bgTargets,
            basalProfile: inputs.basalProfile,
            isf: inputs.isf,
            preferences: preferences,
            carbRatios: inputs.carbRatios,
            tempTargets: inputs.tempTargets,
            model: model,
            clock: now
        )
        try storage.saveProfile(profile)

        // 4. Fetch data
        let glucoseHistory = storage.fetchGlucose(at: now)
        let pumpHistory = storage.fetchPumpEvents(at: now)
        let carbHistory = storage.fetchCarbs(at: now)
        let currentTemp = storage.fetchCurrentTempBasal(at: now)

        // 5. Calculate and store TDD
        let currentTDD = storage.calculateTDD(at: now, basalProfile: inputs.basalProfile)
        try storage.storeTDD(at: now, total: currentTDD)

        let tddRecords = storage.fetchTDDRecords(at: now)
        let twoHoursAgo = now.addingTimeInterval(-2 * 60 * 60)
        let recentTDDRecords = tddRecords.filter { $0.timestamp > twoHoursAgo }

        let averageTDD = tddRecords.isEmpty ? Decimal(0)
            : tddRecords.map(\.total).reduce(0, +) / Decimal(tddRecords.count)
        let past2hoursAverage = recentTDDRecords.isEmpty ? Decimal(0)
            : recentTDDRecords.map(\.total).reduce(0, +) / Decimal(recentTDDRecords.count)

        let weightPercentage = preferences.weightPercentage
        let weightedAverage: Decimal
        if !recentTDDRecords.isEmpty, !tddRecords.isEmpty {
            weightedAverage = weightPercentage * past2hoursAverage + (1 - weightPercentage) * averageTDD
        } else {
            weightedAverage = currentTDD
        }

        // Disable TDD features if insufficient data (need >=75% of expected 5-min points over 7 days)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let weekRecords = tddRecords.filter { $0.timestamp > sevenDaysAgo }
        let sufficientTDD = weekRecords.count >= Int(Double(7 * 288) * 0.75) // 1512 data points
        if !sufficientTDD {
            preferences.useNewFormula = false
            preferences.sigmoid = false
        }

        // 6. Autosens check — recalculate if stale (>30 min) or missing, and enough data
        var autosens = try storage.loadAutosens()
        let autosensAge: TimeInterval
        if let autosensTimestamp = autosens.timestamp {
            autosensAge = now.timeIntervalSince(autosensTimestamp)
        } else {
            autosensAge = .infinity
        }

        if autosensAge > 30 * 60, glucoseHistory.count >= 72 {
            let ratio8h = try AutosensGenerator.generate(
                glucose: glucoseHistory,
                pumpHistory: pumpHistory,
                basalProfile: inputs.basalProfile,
                profile: profile,
                carbs: carbHistory,
                tempTargets: inputs.tempTargets,
                maxDeviations: 96,
                clock: now
            )

            let ratio24h = try AutosensGenerator.generate(
                glucose: glucoseHistory,
                pumpHistory: pumpHistory,
                basalProfile: inputs.basalProfile,
                profile: profile,
                carbs: carbHistory,
                tempTargets: inputs.tempTargets,
                maxDeviations: 288,
                clock: now
            )

            autosens = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h
            autosens.timestamp = now
            try storage.saveAutosens(autosens)
        }

        // 7. Run IOB
        let iobData = try IobGenerator.generate(
            history: pumpHistory,
            profile: profile,
            clock: now,
            autosens: autosens
        )

        // 8. Run Meal
        let mealData = try MealGenerator.generate(
            pumpHistory: pumpHistory,
            profile: profile,
            basalProfile: inputs.basalProfile,
            clock: now,
            carbHistory: carbHistory,
            glucoseHistory: glucoseHistory
        )

        // 9. Construct TrioCustomOrefVariables with TDD data
        let trioVars = TrioCustomOrefVariables(
            average_total_data: currentTDD > 0 ? averageTDD : 0,
            weightedAverage: currentTDD > 0 ? weightedAverage : 1,
            currentTDD: currentTDD,
            past2hoursAverage: currentTDD > 0 ? past2hoursAverage : 0,
            date: now,
            overridePercentage: 100,
            useOverride: false,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: preferences.maxSMBBasalMinutes,
            uamMinutes: preferences.maxUAMSMBBasalMinutes
        )

        // 10. Run determineBasal
        let outputData: Data
        do {
            guard let meal = mealData else {
                outputData = "null".data(using: .utf8)!
                return writeOutput(outputData)
            }

            let result = try DeterminationGenerator.generate(
                profile: profile,
                preferences: preferences,
                currentTemp: currentTemp,
                iobData: iobData,
                mealData: meal,
                autosensData: autosens,
                reservoirData: 100,
                glucose: glucoseHistory,
                microBolusAllowed: true,
                trioCustomOrefVariables: trioVars,
                currentTime: now
            )

            // 11. Store pump events
            if let determination = result {
                if determination.rate != nil, let duration = determination.duration {
                    try storage.storeTempBasal(at: now, rate: determination.rate!, duration: Int(truncating: duration as NSDecimalNumber))
                }
                if let units = determination.units, units > 0 {
                    try storage.storeSMB(at: now, amount: units)
                }
                outputData = try JSONCoding.encoder.encode(determination)
            } else {
                outputData = "null".data(using: .utf8)!
            }

        } catch let determinationError as DeterminationError {
            let errorResponse = DeterminationErrorResponse(error: determinationError.localizedDescription)
            outputData = try JSONCoding.encoder.encode(errorResponse)
        }

        // 12. Save determination to determinations directory
        let determinationsDir = "\(stateDir)/determinations"
        try FileManager.default.createDirectory(atPath: determinationsDir, withIntermediateDirectories: true)
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime]
        timestampFormatter.timeZone = TimeZone.current
        let timestampString = timestampFormatter.string(from: now)
        try outputData.write(to: URL(fileURLWithPath: "\(determinationsDir)/\(timestampString).json"))

        // 13. Output
        writeOutput(outputData)
    }

    private func writeOutput(_ data: Data) {
        if let outputPath = output, outputPath != "-" {
            try? data.write(to: URL(fileURLWithPath: outputPath))
        } else {
            if let outputString = String(data: data, encoding: .utf8) {
                print(outputString)
            }
        }
    }
}
