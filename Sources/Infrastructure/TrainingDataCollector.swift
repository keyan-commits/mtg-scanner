import Foundation
import CoreGraphics
import UIKit

/// Collects annotated card detection data for training a Create ML
/// Object Detection model. Each time the user corrects bounding boxes
/// in the Split Cards tool, the source image + annotations are saved.
///
/// Data format: Create ML Object Detection JSON
/// Directory: Documents/training_data/
@MainActor
final class TrainingDataCollector: Sendable {

    static let shared = TrainingDataCollector()

    private let directoryName = "training_data"

    private var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(directoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Saves an annotated training sample: source image + card bounding boxes.
    func saveTrainingData(image: CGImage, cardRects: [CGRect]) {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let imageName = "photo_\(timestamp).jpg"
        let imageURL = directory.appendingPathComponent(imageName)

        // Save image as JPEG
        let uiImage = UIImage(cgImage: image)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.85) else { return }
        try? jpegData.write(to: imageURL)

        // Build annotations
        let annotations: [[String: Any]] = cardRects.map { rect in
            [
                "label": "mtg_card",
                "coordinates": [
                    "x": rect.midX,
                    "y": rect.midY,
                    "width": rect.width,
                    "height": rect.height
                ]
            ]
        }

        let entry: [String: Any] = [
            "image": imageName,
            "annotations": annotations
        ]

        // Append to annotations.json
        let annotationsURL = directory.appendingPathComponent("annotations.json")
        var existing: [[String: Any]] = []
        if let data = try? Data(contentsOf: annotationsURL),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            existing = array
        }
        existing.append(entry)

        if let jsonData = try? JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted) {
            try? jsonData.write(to: annotationsURL)
        }

        print("[TrainingData] Saved \(imageName) with \(cardRects.count) annotations (total: \(existing.count) images)")
    }

    /// Returns the number of annotated training images collected.
    func trainingDataCount() -> Int {
        let annotationsURL = directory.appendingPathComponent("annotations.json")
        guard let data = try? Data(contentsOf: annotationsURL),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return 0
        }
        return array.count
    }

    /// Returns the training data directory URL for export (AirDrop, Files).
    func exportURL() -> URL {
        return directory
    }
}
