import Foundation
import CoreGraphics
import CoreML
import Vision

/// Detects MTG cards using a custom-trained Core ML object detection model.
/// If no model is bundled in the app, gracefully returns empty results.
/// The model is trained via Create ML using annotated photos collected
/// by TrainingDataCollector.
struct MLCardDetector: Sendable {

    /// The VNCoreMLModel loaded from the bundled .mlmodel, if available.
    private let visionModel: VNCoreMLModel?

    init() {
        // Try bundle first (compiled .mlmodelc from Xcode build)
        if let modelURL = Bundle.main.url(forResource: "MTGCardDetector", withExtension: "mlmodelc"),
           let mlModel = try? MLModel(contentsOf: modelURL),
           let vnModel = try? VNCoreMLModel(for: mlModel) {
            self.visionModel = vnModel
            print("[MLCardDetector] Model loaded from bundle")
        }
        // Try Documents/ (downloaded on first launch via EmbeddingDownloader)
        else if FileManager.default.fileExists(atPath: EmbeddingDownloader.modelDocumentsURL.path),
                let mlModel = try? MLModel(contentsOf: EmbeddingDownloader.modelDocumentsURL),
                let vnModel = try? VNCoreMLModel(for: mlModel) {
            self.visionModel = vnModel
            print("[MLCardDetector] Model loaded from Documents")
        } else {
            self.visionModel = nil
            print("[MLCardDetector] No trained model found — ML detection disabled")
        }
    }

    /// Whether a trained model is available.
    var isAvailable: Bool { visionModel != nil }

    /// Detects cards in the image using the Core ML model.
    /// Returns bounding boxes in CGImage pixel coordinates (origin top-left).
    func detectCards(in image: CGImage) async -> [CGRect] {
        guard let model = visionModel else { return [] }

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[MLCardDetector] Detection failed: \(error)")
            return []
        }

        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        let rects = results
            .filter { $0.confidence > 0.3 }
            .map { obs -> CGRect in
                // Vision coords: origin bottom-left, normalized 0-1
                // Convert to CGImage coords: origin top-left, pixel values
                let bbox = obs.boundingBox
                return CGRect(
                    x: bbox.minX * imgW,
                    y: (1.0 - bbox.maxY) * imgH,
                    width: bbox.width * imgW,
                    height: bbox.height * imgH
                )
            }

        print("[MLCardDetector] Detected \(rects.count) cards (from \(results.count) observations)")
        return rects
    }

    /// Detects and crops cards from the image.
    func detectAndCrop(in image: CGImage) async -> [CGImage] {
        let rects = await detectCards(in: image)
        return rects.compactMap { rect in
            image.cropping(to: rect.integral)
        }
    }
}
