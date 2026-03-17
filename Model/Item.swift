import Darwin
import Foundation
import SwiftData
import UIKit

class SwiftDataController {
    static let shared = SwiftDataController()
    let container: ModelContainer

    init() {
        let appGroupId = Bundle.main.appGroupSuiteName ?? ""
        let schema = Schema([
            Instruction.self,
            LoopDataPoint.self
        ])

        if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            let storeURL = sharedContainer.appendingPathComponent("SharedModel.store")
            let config = ModelConfiguration(url: storeURL)

            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        } else {
            fatalError("Shared app group container could not be created.")
        }
    }
}

@Model final class Instruction {
    // private(set) prevents variables from being changed after initialization.
    private(set) var timestamp: Date
    private(set) var carbohydrates: Double
    private(set) var confidence: String
    private(set) var explanation: String?
    private(set) var processID: Int32
    private static var maxExplanation: Int = 128

    /// Exit initializer early if same process generates command multiple times within the last 5 minutes.
    init?(timestamp: Date = Date(), carbohydrates: Double, confidence: String, explanation: String?) {
        let sharedContext = ModelContext(SwiftDataController.shared.container)
        let descriptor = FetchDescriptor<Instruction>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        do {
            let items: [Instruction] = try sharedContext.fetch(descriptor)
            for item in items where item.processID == getpid() {
                if item.timestamp.timeIntervalSince(timestamp) < 300 {
                    fatalError("Third party feature cannot generate multiple commands within 5 minutes.")
                }
            }
        } catch {
            // if error when fetching previous commands, exit initalizer early without creating new object.
            return nil
        }

        self.timestamp = timestamp
        self.carbohydrates = carbohydrates
        self.confidence = Instruction.checkConfidence(confidence)
        processID = getpid()

        // Setting max explanation limit to 128 characters.
        if let explanation, !explanation.isEmpty {
            self.explanation = String(explanation.prefix(Instruction.maxExplanation))
        }
    }

    /// Return formatted confidence String values. Default to "Low" if given confidence does not conform.
    private static func checkConfidence(_ confidence: String) -> String {
        switch confidence.lowercased() {
        case "high":
            return "High"
        case "medium":
            return "Medium"
        default:
            return "Low"
        }
    }

    /// Return carb entry matching format Trio's computing base expects.
    func toCarbEntry() -> [String: Any] {
        let formattedDate = ISO8601DateFormatter().string(from: timestamp)
        let note = explanation ?? "No explanation given."

        return [
            "carbs": carbohydrates,
            "actualDate": formattedDate,
            "id": UUID().uuidString,
            "note": note,
            "protein": 0,
            "created_at": formattedDate,
            "isFPU": false,
            "fat": 0,
            "enteredBy": "Trio"
        ]
    }
}

@Model final class LoopDataPoint {
    private enum Authorization {
        static let trioPIDKey = "TrioAppProcessID"
    }

    enum Metric {
        static let glucose = "glucose"
        static let iob = "iob"
        static let basal = "basal"
        static let insulinSensitivity = "insulinSensitivity"
    }

    var metric: String
    var timestamp: Date
    var value: Double

    /// Register process ID into app group.
    static func registerCurrentProcess() {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let sharedDefaults = UserDefaults(suiteName: suiteName)
        else {
            return
        }

        sharedDefaults.set(Int(getpid()), forKey: Authorization.trioPIDKey)
    }

    /// Return true iff calling process is Trio.
    private static func authorizePID() -> Bool {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let sharedDefaults = UserDefaults(suiteName: suiteName),
              let authorizedPID = sharedDefaults.object(forKey: Authorization.trioPIDKey) as? Int
        else {
            return false
        }

        return authorizedPID == Int(getpid())
    }

    init(metric: String, timestamp: Date, value: Double) {
        guard Self.authorizePID() else {
            fatalError("LoopDataPoint initialization is restricted to the authorized Trio app process.")
        }

        self.metric = metric
        self.timestamp = timestamp
        self.value = value
    }
}
