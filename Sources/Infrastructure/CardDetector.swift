import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Detects a single MTG card rectangle in a photo, applies perspective correction,
/// and returns a cleanly cropped card image.
struct CardDetector: Sendable {

    /// Detects a single card, perspective-corrects it, and returns the cropped card.
    func detectAndCrop(from image: CGImage) async -> CGImage? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.55
        request.maximumAspectRatio = 0.85
        request.minimumSize = 0.15
        request.maximumObservations = 1
        request.minimumConfidence = 0.6
        request.quadratureTolerance = 20

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }
        return applyPerspectiveCorrection(to: image, observation: observation)
    }

    // MARK: - Perspective Correction

    private func applyPerspectiveCorrection(
        to image: CGImage,
        observation: VNRectangleObservation
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

        let context = CIContext()
        return context.createCGImage(corrected, from: corrected.extent)
    }
}
