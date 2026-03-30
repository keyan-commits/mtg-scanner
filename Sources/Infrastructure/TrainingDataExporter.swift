import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Training Data Models

struct TrainingAnnotation: Codable {
    let image: String
    let annotations: [BoundingBox]
}

struct BoundingBox: Codable {
    let label: String
    let coordinates: Coordinates
}

struct Coordinates: Codable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

// MARK: - Training Data Exporter

/// Exports grid-confirmed card photos as CreateML-compatible training data.
/// Images are saved as JPEG files alongside annotation JSON files in the
/// Application Support/training_data/ directory.
struct TrainingDataExporter: Sendable {
    private let baseURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.baseURL = appSupport.appendingPathComponent("training_data", isDirectory: true)
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: - Export

    /// Exports a source image with grid cell bounding boxes as CreateML training data.
    /// - Parameters:
    ///   - image: The source CGImage containing the card grid.
    ///   - gridCells: Array of grid cell positions with row, column, and CGRect coordinates.
    /// - Throws: File system errors if the image or annotation cannot be saved.
    func export(
        image: CGImage,
        gridCells: [(row: Int, col: Int, rect: CGRect)]
    ) throws {
        try ensureDirectoryExists()

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let imageName = "grid_\(timestamp).jpg"
        let imageURL = baseURL.appendingPathComponent(imageName)

        // Save image as JPEG
        try saveJPEG(image: image, to: imageURL)

        // Build annotations
        let annotations = gridCells.map { cell in
            BoundingBox(
                label: "mtg_card",
                coordinates: Coordinates(
                    x: Int(cell.rect.midX),
                    y: Int(cell.rect.midY),
                    width: Int(cell.rect.width),
                    height: Int(cell.rect.height)
                )
            )
        }

        let annotation = TrainingAnnotation(
            image: imageName,
            annotations: annotations
        )

        // Save annotation JSON
        let annotationURL = baseURL.appendingPathComponent("grid_\(timestamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(annotation)
        try jsonData.write(to: annotationURL)
    }

    // MARK: - Query

    /// Returns the number of exported training images in the training data directory.
    func trainingDataCount() -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }
        return contents.filter { $0.pathExtension == "jpg" }.count
    }

    /// Zips the entire training data directory for sharing and returns the zip file URL.
    /// - Returns: The URL of the created zip file, or nil if the directory is empty or zipping fails.
    func exportAll() -> URL? {
        let count = trainingDataCount()
        guard count > 0 else { return nil }

        let zipName = "mtg_training_data_\(Int(Date().timeIntervalSince1970)).zip"
        let tempDir = FileManager.default.temporaryDirectory
        let zipURL = tempDir.appendingPathComponent(zipName)

        // Remove existing zip if present
        try? FileManager.default.removeItem(at: zipURL)

        do {
            // Use NSFileCoordinator to create a zip archive
            var error: NSError?
            NSFileCoordinator().coordinate(
                readingItemAt: baseURL,
                options: .forUploading,
                error: &error
            ) { zippedURL in
                try? FileManager.default.copyItem(at: zippedURL, to: zipURL)
            }

            if error != nil {
                return nil
            }

            return FileManager.default.fileExists(atPath: zipURL.path) ? zipURL : nil
        }
    }

    // MARK: - Private Helpers

    private func ensureDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            try FileManager.default.createDirectory(
                at: baseURL,
                withIntermediateDirectories: true
            )
        }
    }

    private func saveJPEG(image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw TrainingDataError.imageWriteFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw TrainingDataError.imageWriteFailed
        }
    }
}

// MARK: - Errors

enum TrainingDataError: Error {
    case imageWriteFailed
}
