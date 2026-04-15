import Foundation
import UIKit
import CoreGraphics

/// Saves crop images paired with user-corrected stack counts for future ML training.
/// Data is written to Documents/stack_training/ as JPEG images plus a manifest JSON.
final class StackCountTrainer {

    static let shared = StackCountTrainer()

    private let directoryName = "stack_training"
    private let manifestName = "manifest.json"
    private let queue = DispatchQueue(label: "StackCountTrainer", qos: .utility)

    private var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(directoryName, isDirectory: true)
    }

    private var manifestURL: URL {
        directory.appendingPathComponent(manifestName)
    }

    private init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Public

    /// Saves a crop image and its correct stack count to disk.
    /// Thread-safe — can be called from any thread.
    func saveTrainingData(image: CGImage, count: Int) {
        let uiImage = UIImage(cgImage: image)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.85) else { return }

        queue.async { [self] in
            let id = Int(Date().timeIntervalSince1970 * 1000)
            let filename = "stack_\(id).jpg"
            let fileURL = directory.appendingPathComponent(filename)

            do {
                try jpegData.write(to: fileURL)
            } catch {
                print("[StackCountTrainer] Failed to write image: \(error)")
                return
            }

            // Append entry to manifest
            var manifest = loadManifest()
            manifest.append(TrainingEntry(image: filename, count: count))
            saveManifest(manifest)

            print("[StackCountTrainer] Saved \(filename) with count=\(count) (total: \(manifest.count) samples)")
        }
    }

    /// Returns the total number of training samples saved.
    var sampleCount: Int {
        loadManifest().count
    }

    // MARK: - Manifest I/O

    private struct TrainingEntry: Codable {
        let image: String
        let count: Int
    }

    private func loadManifest() -> [TrainingEntry] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([TrainingEntry].self, from: data)) ?? []
    }

    private func saveManifest(_ entries: [TrainingEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
