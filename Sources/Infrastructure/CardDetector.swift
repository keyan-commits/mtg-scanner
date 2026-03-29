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

    /// Detects cards, including subdividing wide rectangles that contain multiple
    /// side-by-side cards (which Vision sees as one wide rectangle).
    func detectAndCropAllCards(from image: CGImage) -> [CGImage] {
        // First try standard multi-card detection
        let observations = detectRectangleObservations(from: image)

        // Filter out tiny detections — a card must be at least 100px in each dimension
        let minPixels = 100
        let filtered = observations.filter { obs in
            let w = Int(obs.boundingBox.width * CGFloat(image.width))
            let h = Int(obs.boundingBox.height * CGFloat(image.height))
            return w >= minPixels && h >= minPixels
        }

        if filtered.count > 1 {
            // Multiple cards detected — crop each
            return filtered.compactMap { cropCard(from: image, observation: $0) }
        }

        if let single = filtered.first {
            guard let cropped = cropCard(from: image, observation: single) else {
                return []
            }

            let aspectRatio = Double(cropped.width) / Double(cropped.height)

            // Single card aspect ratio is ~0.716 (w/h)
            // Subdivide based on aspect ratio to handle rows and grids
            if aspectRatio > 1.2 {
                // Wide: horizontal row of cards
                let cols = max(2, Int(round(aspectRatio / 0.716)))
                print("[MTGScanner] Wide rectangle (ratio \(String(format: "%.2f", aspectRatio))), subdividing into \(cols) columns")
                return subdivideImage(cropped, into: cols)
            }

            if aspectRatio > 0.5 && aspectRatio <= 0.85 {
                // Normal single card
                return [cropped]
            }

            // Aspect ratio ~0.85-1.2 could be 2x2 grid or similar
            // 2x2 grid of cards: width ~= 2*63=126, height ~= 2*88=176, ratio ~0.716
            // Check if it's a grid by seeing if subdividing 2x2 gives card-shaped segments
            if aspectRatio >= 0.5 && aspectRatio <= 1.2 {
                let rows = max(1, Int(round(1.0 / (aspectRatio / 0.716 * 0.5))))
                let cols = max(1, Int(round(aspectRatio / 0.716 * Double(rows))))
                if rows >= 2 || cols >= 2 {
                    print("[MTGScanner] Grid detected (ratio \(String(format: "%.2f", aspectRatio))), subdividing into \(rows)x\(cols)")
                    return subdivideGrid(cropped, rows: rows, cols: cols)
                }
            }

            return [cropped]
        }

        // No rectangles detected — try the full image as a single card
        return []
    }

    /// Subdivides a wide image into equal-width card segments (horizontal row).
    private func subdivideImage(_ image: CGImage, into cols: Int) -> [CGImage] {
        return subdivideGrid(image, rows: 1, cols: cols)
    }

    /// Subdivides an image into a grid of equal-sized card segments.
    private func subdivideGrid(_ image: CGImage, rows: Int, cols: Int) -> [CGImage] {
        let cardWidth = image.width / cols
        let cardHeight = image.height / rows

        var results: [CGImage] = []
        for row in 0..<rows {
            for col in 0..<cols {
                let x = col * cardWidth
                let y = row * cardHeight
                let rect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
                if let cropped = image.cropping(to: rect) {
                    results.append(cropped)
                }
            }
        }
        return results
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
