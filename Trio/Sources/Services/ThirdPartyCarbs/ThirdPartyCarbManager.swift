import Foundation
import SwiftDate
import Swinject

struct ThirdPartyCarbEntry: Decodable, Equatable {
    let timestamp: Date
    let carbs: Double // assuming in grams.
    let source: String

    enum CodingKeys: String, CodingKey {
        case timestamp
        case carbs = "carbohydrates"
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestampString = try container.decode(String.self, forKey: .timestamp)
        guard let timestamp = ThirdPartyCarbEntry.parseTimestamp(timestampString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Invalid ISO-8601 timestamp."
            )
        }

        self.timestamp = timestamp
        carbs = try container.decode(Double.self, forKey: .carbs)
        source = try container.decode(String.self, forKey: .source)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

protocol ThirdPartyCarbManager {
    var latestEntry: ThirdPartyCarbEntry? { get }
    func refresh()
}

final class BaseThirdPartyCarbManager: ThirdPartyCarbManager, Injectable {
    private enum Constants {
        static let fileName = "third_party_carbs.json"
    }

    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)
    private let queue = DispatchQueue(label: "ThirdPartyCarbManager.queue")

    private(set) var latestEntry: ThirdPartyCarbEntry?

    init(resolver: Resolver) {
        injectServices(resolver)
        timer.eventHandler = { [weak self] in
            self?.refresh()
        }
        timer.fire()
        timer.resume()
    }

    func refresh() {
        queue.async { [weak self] in
            self?.readSharedCarbFile()
        }
    }

    private func readSharedCarbFile() {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
        else {
            return
        }

        let fileURL = containerURL.appendingPathComponent(Constants.fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            return
        }

        let decoder = JSONDecoder()
        do {
            let entry = try decoder.decode(ThirdPartyCarbEntry.self, from: data)
            if entry != latestEntry {
                latestEntry = entry
            }
        } catch {
            return
        }
    }
}
