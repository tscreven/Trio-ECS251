import Foundation
import SwiftData
import UIKit

class SwiftDataController {
    static let shared = SwiftDataController()
    let container: ModelContainer

    init() {
        let appGroupId = Bundle.main.appGroupSuiteName ?? ""
        let schema = Schema([
            Item.self
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

@Model final class Item {
    var timestamp: Date
    var carbohydrates: Double
    var confidence: String
    var explanation: String?
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
