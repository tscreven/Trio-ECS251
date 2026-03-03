import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

// MARK: - Input struct for direct JSON decoding

struct AutosensInputs: Decodable {
    let glucose: [BloodGlucose]
    let history: [PumpHistoryEvent]
    let basalProfile: [BasalProfileEntry]
    let profile: Profile
    let carbs: [CarbsEntry]
    let tempTargets: [TempTarget]
    let clock: Date

    private enum CodingKeys: String, CodingKey {
        case glucose
        case history
        case basalProfile
        case profile
        case carbs
        case tempTargets
        case clock
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        glucose = try container.decode([BloodGlucose].self, forKey: .glucose)
        history = try container.decode([PumpHistoryEvent].self, forKey: .history)
        basalProfile = try container.decode([BasalProfileEntry].self, forKey: .basalProfile)
        profile = try container.decode(Profile.self, forKey: .profile)
        carbs = try container.decode([CarbsEntry].self, forKey: .carbs)
        tempTargets = try container.decode([TempTarget].self, forKey: .tempTargets)

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

// MARK: - Autosens Command

struct AutosensCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "autosens",
        abstract: "Calculate autosensitivity ratio."
    )

    @Option(name: .shortAndLong, help: "Input file path (use '-' for STDIN)") var input: String?

    @Option(name: .shortAndLong, help: "Output file path (use '-' for STDOUT)") var output: String?

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
        let autosensInput = try JSONCoding.decoder.decode(AutosensInputs.self, from: inputData)

        // Generate autosens with 8h window (96 deviations)
        let ratio8h = try AutosensGenerator.generate(
            glucose: autosensInput.glucose,
            pumpHistory: autosensInput.history,
            basalProfile: autosensInput.basalProfile,
            profile: autosensInput.profile,
            carbs: autosensInput.carbs,
            tempTargets: autosensInput.tempTargets,
            maxDeviations: 96,
            clock: autosensInput.clock
        )

        // Generate autosens with 24h window (288 deviations)
        let ratio24h = try AutosensGenerator.generate(
            glucose: autosensInput.glucose,
            pumpHistory: autosensInput.history,
            basalProfile: autosensInput.basalProfile,
            profile: autosensInput.profile,
            carbs: autosensInput.carbs,
            tempTargets: autosensInput.tempTargets,
            maxDeviations: 288,
            clock: autosensInput.clock
        )

        // Take the lower ratio
        let result = ratio8h.ratio < ratio24h.ratio ? ratio8h : ratio24h

        // Encode output
        let outputData = try JSONCoding.encoder.encode(result)

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
