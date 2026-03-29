import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Detects MTG card rectangles in photos, applies perspective correction,
/// and returns cleanly cropped card images. Supports both single and multi-card detection.
struct CardDetector: Sendable {

    // MARK: - Single Card Detection

    /// Detects a single card in the image, perspective-corrects it, and returns the cropped card.
    /// Returns nil if no card-shaped rectangle is detected.
    func detectAndCrop(from image: CGImage) async -> CGImage? {
        let observations = detectRectangles(in: image, maximumObservations: 1, minimumSize: 0.15)
        guard let observation = observations.first else { return nil }
        return applyPerspectiveCorrection(to: image, observation: observation)
    }

    // MARK: - Multi-Card Detection

    /// Detects all card-shaped rectangle observations in the image.
    /// Returns deduplicated observations sorted left-to-right.
    /// Does NOT crop — call `cropCard(from:observation:)` individually to control memory.
    func detectRectangleObservations(from image: CGImage) -> [VNRectangleObservation] {
        let observations = detectRectangles(in: image, maximumObservations: 10, minimumSize: 0.03)
        guard !observations.isEmpty else { return [] }

        let deduplicated = deduplicateObservations(observations)
        return deduplicated.sorted { $0.boundingBox.midX < $1.boundingBox.midX }
    }

    /// Crops a single card from the image using a detected rectangle observation.
    func cropCard(from image: CGImage, observation: VNRectangleObservation) -> CGImage? {
        applyPerspectiveCorrection(to: image, observation: observation)
    }

    /// Detects and crops all cards at once. Use for small card counts only.
    func detectAndCropAll(from image: CGImage) async -> [CGImage] {
        let observations = detectRectangleObservations(from: image)
        return observations.compactMap { cropCard(from: image, observation: $0) }
    }

    // MARK: - Rectangle Detection

    private func detectRectangles(
        in image: CGImage,
        maximumObservations: Int,
        minimumSize: Float
    ) -> [VNRectangleObservation] {
        let request = VNDetectRectanglesRequest()
        // MTG card aspect ratio: 63mm x 88mm ≈ 0.716
        request.minimumAspectRatio = 0.55
        request.maximumAspectRatio = 0.85
        request.minimumSize = minimumSize
        request.maximumObservations = maximumObservations
        request.minimumConfidence = 0.6
        request.quadratureTolerance = 20

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return request.results ?? []
    }

    // MARK: - Perspective Correction

    private func applyPerspectiveCorrection(
        to image: CGImage,
        observation: VNRectangleObservation,
        context: CIContext? = nil
    ) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let size = ciImage.extent.size

        let topLeft = CGPoint(x: observation.topLeft.x * size.width,
                              y: observation.topLeft.y * size.height)
        let topRight = CGPoint(x: observation.topRight.x * size.width,
                               y: observation.topRight.y * size.height)
        let bottomLeft = CGPoint(x: observation.bottomLeft.x * size.width,
                                 y: observation.bottomLeft.y * size.height)
        let bottomRight = CGPoint(x: observation.bottomRight.x * size.width,
                                  y: observation.bottomRight.y * size.height)

        let corrected = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight)
        ])

        let ctx = context ?? CIContext()
        return ctx.createCGImage(corrected, from: corrected.extent)
    }

    // MARK: - Deduplication

    /// Removes overlapping rectangle observations (IoU > 0.5).
    /// Keeps the observation with higher confidence.
    private func deduplicateObservations(_ observations: [VNRectangleObservation]) -> [VNRectangleObservation] {
        var kept: [VNRectangleObservation] = []

        for observation in observations.sorted(by: { $0.confidence > $1.confidence }) {
            let isDuplicate = kept.contains { existing in
                iou(existing.boundingBox, observation.boundingBox) > 0.5
            }
            if !isDuplicate {
                kept.append(observation)
            }
        }

        return kept
    }

    /// Intersection over Union of two CGRects.
    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
