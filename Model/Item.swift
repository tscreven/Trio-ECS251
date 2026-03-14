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

struct CarbEstimationResult: Codable {
    let carbohydrates: Double
    let confidence: Confidence
    let explanation: String?

    enum Confidence: String, Codable {
        case low
        case medium
        case high
    }
}

@Model final class Instruction {
    // private(set) prevents variables from being changed after initialization.
    private(set) var timestamp: Date
    private(set) var carbohydrates: Double
    private(set) var confidence: String
    private(set) var explanation: String?
    @Attribute(.externalStorage) var imageData: Data?

    init(timestamp: Date = Date(), carbohydrates: Double, confidence: String, explanation: String?, imageData: Data?) {
        self.timestamp = timestamp
        self.carbohydrates = carbohydrates
        self.confidence = confidence
        self.explanation = explanation
        self.imageData = imageData
    }

    convenience init(result: CarbEstimationResult, image: UIImage?) {
        let imageData = image?.jpegData(compressionQuality: 0.7)
        self.init(
            timestamp: Date(),
            carbohydrates: result.carbohydrates,
            confidence: result.confidence.rawValue,
            explanation: result.explanation,
            imageData: imageData
        )
    }

    var confidenceEnum: CarbEstimationResult.Confidence {
        CarbEstimationResult.Confidence(rawValue: confidence) ?? .low
    }

    var image: UIImage? {
        guard let imageData = imageData else { return nil }
        return UIImage(data: imageData)
    }

    func toCarbEntry() -> [String: Any] {
        let formattedDate = ISO8601DateFormatter().string(from: timestamp)

        return [
            "carbs": carbohydrates,
            "actualDate": formattedDate,
            "id": UUID().uuidString,
            "note": NSNull(),
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
        static let trioProcessIDKey = "TrioAppProcessID"
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

    static func registerCurrentProcessAsAuthorizedCreator() {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let sharedDefaults = UserDefaults(suiteName: suiteName)
        else {
            return
        }

        sharedDefaults.set(Int(getpid()), forKey: Authorization.trioProcessIDKey)
    }

    private static func currentProcessIsAuthorizedCreator() -> Bool {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let sharedDefaults = UserDefaults(suiteName: suiteName),
              let authorizedPID = sharedDefaults.object(forKey: Authorization.trioProcessIDKey) as? Int
        else {
            return false
        }

        return authorizedPID == Int(getpid())
    }

    init(metric: String, timestamp: Date, value: Double) {
        guard Self.currentProcessIsAuthorizedCreator() else {
            fatalError("LoopDataPoint initialization is restricted to the authorized Trio app process.")
        }

        self.metric = metric
        self.timestamp = timestamp
        self.value = value
    }
}
