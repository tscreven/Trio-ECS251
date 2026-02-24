import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

// MARK: - Input struct for direct JSON decoding

struct DetermineBasalInputs: Decodable {
    let glucose: [BloodGlucose]
    let currentTemp: TempBasal
    let iob: [IobResult]
    let profile: Profile
    let autosens: Autosens?
    let meal: ComputedCarbs?
    let microBolusAllowed: Bool
    let reservoir: Decimal?
    let pumpHistory: [PumpHistoryEvent]
    let preferences: Preferences
    let basalProfile: [BasalProfileEntry]
    let trioCustomOrefVariables: TrioCustomOrefVariables
    let clock: Date

    private enum CodingKeys: String, CodingKey {
        case glucose
        case currentTemp
        case iob
        case profile
        case autosens
        case meal
        case microBolusAllowed
        case reservoir
        case pumpHistory
        case preferences
        case basalProfile
        case trioCustomOrefVariables
        case clock
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        glucose = try container.decode([BloodGlucose].self, forKey: .glucose)
        currentTemp = try container.decode(TempBasal.self, forKey: .currentTemp)
        iob = try container.decode([IobResult].self, forKey: .iob)
        profile = try container.decode(Profile.self, forKey: .profile)
        autosens = try container.decodeIfPresent(Autosens.self, forKey: .autosens)
        meal = try container.decodeIfPresent(ComputedCarbs.self, forKey: .meal)
        microBolusAllowed = try container.decode(Bool.self, forKey: .microBolusAllowed)
        reservoir = try container.decodeIfPresent(Decimal.self, forKey: .reservoir)
        pumpHistory = try container.decode([PumpHistoryEvent].self, forKey: .pumpHistory)
        preferences = try container.decode(Preferences.self, forKey: .preferences)
        basalProfile = try container.decode([BasalProfileEntry].self, forKey: .basalProfile)
        trioCustomOrefVariables = try container.decode(TrioCustomOrefVariables.self, forKey: .trioCustomOrefVariables)

        // Handle clock as either timestamp number or ISO8601 string
        if let timestamp = try? container.decode(Double.self, forKey: .clock) {
            clock = Date(timeIntervalSince1970: timestamp)
        } else if let dateString = try? container.decode(String.self, forKey: .clock) {
            if let date = Formatter.iso8601withFractionalSeconds.date(from: dateString) ??
                Formatter.iso8601.date(from: dateString)
            {
                clock = date
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .clock,
                    in: container,
                    debugDescription: "Invalid date format"
                )
            }
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .clock,
                in: container,
                debugDescription: "Expected number or string for clock"
            )
        }
    }
}

// MARK: - DetermineBasal Command

struct DetermineBasal: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "determineBasal",
        abstract: "Determine basal rate adjustments based on current state."
    )

    @Option(name: .shortAndLong, help: "Input file path (use '-' for STDIN)")  var input: String?

    @Option(name: .shortAndLong, help: "Output file path (use '-' for STDOUT)")  var output: String?

    func run() throws {
        // Read input
        let inputData: Data
        if let inputPath = input, inputPath != "-" {
            let url = URL(fileURLWithPath: inputPath)
            inputData = try Data(contentsOf: url)
        } else {
            inputData = FileHandle.standardInput.readDataToEndOfFile()
        }

        // Decode input
        let determineBasalInput = try JSONCoding.decoder.decode(DetermineBasalInputs.self, from: inputData)

        // Run the algorithm
        let outputData: Data
        do {
            guard let mealData = determineBasalInput.meal, let autosensData = determineBasalInput.autosens else {
                throw DeterminationError.missingInputs
            }

            let result = try DeterminationGenerator.generate(
                profile: determineBasalInput.profile,
                preferences: determineBasalInput.preferences,
                currentTemp: determineBasalInput.currentTemp,
                iobData: determineBasalInput.iob,
                mealData: mealData,
                autosensData: autosensData,
                reservoirData: determineBasalInput.reservoir ?? 100,
                glucose: determineBasalInput.glucose,
                microBolusAllowed: determineBasalInput.microBolusAllowed,
                trioCustomOrefVariables: determineBasalInput.trioCustomOrefVariables,
                currentTime: determineBasalInput.clock
            )

            if let result = result {
                outputData = try JSONCoding.encoder.encode(result)
            } else {
                outputData = "null".data(using: .utf8)!
            }

        } catch let determinationError as DeterminationError {
            // DeterminationError is returned as {"error": "..."} JSON (matching iOS behavior)
            let errorResponse = DeterminationErrorResponse(error: determinationError.localizedDescription)
            outputData = try JSONCoding.encoder.encode(errorResponse)
        }

        // Write output
        if let outputPath = output, outputPath != "-" {
            let url = URL(fileURLWithPath: outputPath)
            try outputData.write(to: url)
        } else {
            if let outputString = String(data: outputData, encoding: .utf8) {
                print(outputString)
            }
        }
    }
}
