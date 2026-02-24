import ArgumentParser
import Foundation
import OrefSwiftAlgorithm
import OrefSwiftModels

// MARK: - Input struct for direct JSON decoding (avoids JSONSerialization precision loss)

struct IobInputs: Decodable {
    let history: [PumpHistoryEvent]
    let profile: Profile
    let clock: Date
    let autosens: Autosens?

    private enum CodingKeys: String, CodingKey {
        case history
        case profile
        case clock
        case autosens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        history = try container.decode([PumpHistoryEvent].self, forKey: .history)
        profile = try container.decode(Profile.self, forKey: .profile)
        autosens = try container.decodeIfPresent(Autosens.self, forKey: .autosens)

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

// MARK: - IOB Command

struct IOB: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iob",
        abstract: "Calculate insulin on board (IOB)."
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
            // Read from stdin
            inputData = FileHandle.standardInput.readDataToEndOfFile()
        }

        // Decode input directly with JSONDecoder (preserves Decimal precision)
        let iobInput = try JSONCoding.decoder.decode(IobInputs.self, from: inputData)

        // Generate IOB
        let iobResult = try IobGenerator.generate(
            history: iobInput.history,
            profile: iobInput.profile,
            clock: iobInput.clock,
            autosens: iobInput.autosens
        )

        // Encode output using JSONEncoder directly (matching iOS approach)
        let outputData = try JSONCoding.encoder.encode(iobResult)

        // Write output
        if let outputPath = output, outputPath != "-" {
            let url = URL(fileURLWithPath: outputPath)
            try outputData.write(to: url)
        } else {
            // Write to stdout
            if let outputString = String(data: outputData, encoding: .utf8) {
                print(outputString)
            }
        }
    }
}
