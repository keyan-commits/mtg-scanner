import Foundation
import CoreGraphics
import Vision

// MARK: - Error Types

/// Errors that can occur during text recognition.
enum TextRecognitionError: Error, Sendable, Equatable {
    case noTextFound
    case imageProcessingFailed
}

// MARK: - Protocol

/// Defines the contract for text recognition on card images.
protocol TextRecognizerProtocol: Sendable {
    /// Recognizes text in the given image and returns scan results
    /// sorted by vertical position (topmost first) with low-confidence
    /// results filtered out.
    func recognizeText(in image: CGImage) async throws -> [ScanResult]
}

// MARK: - Vision Implementation

/// Recognizes text in card images using Apple's Vision framework.
///
/// Uses VNRecognizeTextRequest with accurate recognition level to extract
/// text observations, then maps them to `ScanResult` values sorted by
/// vertical position (card name at top) and filtered by a minimum
/// confidence threshold.
struct VisionTextRecognizer: TextRecognizerProtocol {

    /// Minimum confidence threshold for including a recognized text observation.
    private let minimumConfidence: Float

    /// Creates a recognizer with the given confidence threshold.
    /// - Parameter minimumConfidence: Minimum confidence to keep a result. Defaults to 0.5.
    init(minimumConfidence: Float = 0.5) {
        self.minimumConfidence = minimumConfidence
    }

    func recognizeText(in image: CGImage) async throws -> [ScanResult] {
        let observations = try await performRecognition(on: image)

        guard !observations.isEmpty else {
            throw TextRecognitionError.noTextFound
        }

        let scanResults = observations.compactMap { observation -> ScanResult? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            guard candidate.confidence >= minimumConfidence else {
                return nil
            }

            let text = candidate.string
            guard text.count >= 2 else {
                return nil
            }

            return ScanResult(
                recognizedText: text,
                confidence: Double(candidate.confidence),
                boundingBox: observation.boundingBox
            )
        }

        return ScanResultSorter.sortByVerticalPosition(scanResults)
    }

    /// Performs the Vision text recognition request on the given image.
    private func performRecognition(
        on image: CGImage
    ) async throws -> [VNRecognizedTextObservation] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01

        do {
            try handler.perform([request])
        } catch {
            throw TextRecognitionError.imageProcessingFailed
        }

        return request.results ?? []
    }
}

// MARK: - Sorting Utilities

/// Sorts scan results by their vertical position in the image.
enum ScanResultSorter: Sendable {

    /// Sorts results by descending Y origin of the bounding box.
    ///
    /// In Vision's coordinate system, Y increases upward, so higher Y values
    /// correspond to text nearer the top of the card. The card name is
    /// typically the topmost text element.
    static func sortByVerticalPosition(_ results: [ScanResult]) -> [ScanResult] {
        results.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
    }
}

// MARK: - Filtering Utilities

/// Filters scan results by confidence and text length thresholds.
enum ScanResultFilter: Sendable {

    /// Keeps only results whose confidence meets or exceeds the minimum.
    static func filterByConfidence(
        _ results: [ScanResult],
        minimumConfidence: Double
    ) -> [ScanResult] {
        results.filter { $0.confidence >= minimumConfidence }
    }

    /// Keeps only results whose recognized text meets or exceeds the minimum length.
    static func filterByMinimumLength(
        _ results: [ScanResult],
        minimumLength: Int
    ) -> [ScanResult] {
        results.filter { $0.recognizedText.count >= minimumLength }
    }
}
