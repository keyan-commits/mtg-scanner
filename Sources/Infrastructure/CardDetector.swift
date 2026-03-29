import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Detects an MTG card rectangle in a photo, applies perspective correction,
/// and returns a cleanly cropped card image.
struct CardDetector: Sendable {

    /// Detects the card in the image, perspective-corrects it, and returns the cropped card.
    /// Returns nil if no card-shaped rectangle is detected.
    func detectAndCrop(from image: CGImage) async -> CGImage? {
        // Step 1: Detect card rectangle
        let request = VNDetectRectanglesRequest()
        // MTG card aspect ratio: 63mm x 88mm ≈ 0.716
        request.minimumAspectRatio = 0.60
        request.maximumAspectRatio = 0.85
        request.minimumSize = 0.15  // card should fill at least 15% of image
        request.maximumObservations = 1
        request.minimumConfidence = 0.7
        request.quadratureTolerance = 20  // allow up to 20 degrees skew

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else {
            return nil
        }

        // Step 2: Apply perspective correction using CIPerspectiveCorrection
        return applyPerspectiveCorrection(to: image, observation: observation)
    }

    /// Applies CIPerspectiveCorrection to straighten and crop the detected card.
    private func applyPerspectiveCorrection(
        to image: CGImage,
        observation: VNRectangleObservation
    ) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let size = ciImage.extent.size

        // Vision coordinates are normalized (0-1) with origin at bottom-left,
        // which matches CIImage coordinate system — no Y-flip needed.
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
