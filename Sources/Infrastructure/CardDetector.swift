import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Detects a single MTG card rectangle in a photo, applies perspective correction,
/// and returns a cleanly cropped card image.
struct CardDetector: Sendable {

    /// Detects a single card, perspective-corrects it, and returns the cropped card.
    func detectAndCrop(from image: CGImage) async -> CGImage? {
        let results = detectRectangles(in: image, maxObservations: 1)
        guard let observation = results.first else { return nil }
        return applyPerspectiveCorrection(to: image, observation: observation)
    }

    /// Detects ALL card-shaped rectangles in a photo (up to `maxCards`)
    /// and returns each one perspective-corrected. Used by the deck
    /// photo scan to find individual cards without a fixed grid — the
    /// cards can be at any position, angle, or spacing.
    ///
    /// This replaces the grid-based approach which cut off card edges
    /// (losing the collector number / set code at the bottom) and
    /// processed empty playmat cells as phantom cards.
    func detectAndCropAll(from image: CGImage, maxCards: Int = 20) async -> [CGImage] {
        let raw = detectRectangles(in: image, maxObservations: maxCards * 3)
        let nmsFiltered = Self.suppressOverlapping(raw, iouThreshold: 0.3)
        let sizeFiltered = Self.filterByConsistentSize(nmsFiltered, minRatio: 0.2)

        // Perspective-correct each surviving rectangle, then verify
        // it actually contains text (real cards have a title at the
        // top; playmat logos, mat edges, and other non-card rectangles
        // don't). This ~20ms text-presence check prevents phantom
        // detections from decorative rectangles on the playmat.
        var verified: [CGImage] = []
        for obs in sizeFiltered {
            guard let corrected = applyPerspectiveCorrection(to: image, observation: obs) else { continue }
            if await hasText(corrected) {
                verified.append(corrected)
            } else {
                print("[MTGScanner] Dropped rectangle — no text detected (likely playmat/background)")
            }
        }
        print("[MTGScanner] Rectangle detection: \(raw.count) raw → \(nmsFiltered.count) NMS → \(sizeFiltered.count) size → \(verified.count) text-verified")
        return verified
    }

    /// Fast check (~20ms) for whether an image contains any text
    /// regions. Uses `VNDetectTextRectanglesRequest` which finds text
    /// bounding boxes without actually reading the text — much faster
    /// than full OCR. A real MTG card always has text (card name at
    /// minimum); a playmat logo or mat edge does not.
    private func hasText(_ image: CGImage) async -> Bool {
        let request = VNDetectTextRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let count = request.results?.count ?? 0
            // A real card has 5+ text regions (name, type, rules, copyright, etc.)
            // A noisy background might have 1-2 spurious detections.
            return count >= 3
        } catch {
            return true // On failure, assume it's a card (safe fallback)
        }
    }

    /// Drops detections whose bounding-box area is less than
    /// `minRatio` of the largest detection. In a multi-card photo,
    /// all real cards are similar sizes; sub-regions (art frame,
    /// text box) are always smaller.
    private static func filterByConsistentSize(
        _ observations: [VNRectangleObservation],
        minRatio: Float
    ) -> [VNRectangleObservation] {
        guard let maxArea = observations.map({ area($0) }).max(),
              maxArea > 0 else { return observations }
        return observations.filter { area($0) / maxArea >= minRatio }
    }

    /// Filters overlapping rectangle observations. When two rectangles
    /// overlap by more than `iouThreshold` (Intersection over Union),
    /// the smaller one is dropped — it's typically a sub-region of
    /// the larger card (art frame, text box).
    private static func suppressOverlapping(
        _ observations: [VNRectangleObservation],
        iouThreshold: Float
    ) -> [VNRectangleObservation] {
        // Sort by area descending — larger rectangles are more likely
        // to be full cards than inner sub-regions.
        let sorted = observations.sorted { a, b in
            area(a) > area(b)
        }
        var kept: [VNRectangleObservation] = []
        for candidate in sorted {
            let dominated = kept.contains { existing in
                iou(existing, candidate) > iouThreshold
            }
            if !dominated {
                kept.append(candidate)
            }
        }
        return kept
    }

    private static func area(_ obs: VNRectangleObservation) -> Float {
        let rect = obs.boundingBox
        return Float(rect.width * rect.height)
    }

    /// Intersection-over-Union of two bounding boxes.
    private static func iou(_ a: VNRectangleObservation, _ b: VNRectangleObservation) -> Float {
        let ar = a.boundingBox
        let br = b.boundingBox
        let interX = max(0, min(ar.maxX, br.maxX) - max(ar.minX, br.minX))
        let interY = max(0, min(ar.maxY, br.maxY) - max(ar.minY, br.minY))
        let interArea = Float(interX * interY)
        let areaA = Float(ar.width * ar.height)
        let areaB = Float(br.width * br.height)
        let unionArea = areaA + areaB - interArea
        guard unionArea > 0 else { return 0 }
        return interArea / unionArea
    }

    private func detectRectangles(in image: CGImage, maxObservations: Int) -> [VNRectangleObservation] {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.55
        request.maximumAspectRatio = 0.85
        request.minimumSize = 0.05   // Lower threshold to catch small/distant cards
        request.maximumObservations = 0  // Unlimited — let NMS + size filter do the pruning
        request.minimumConfidence = 0.3  // More permissive — text-verification rejects phantoms
        request.quadratureTolerance = 25 // Tolerate more skew (cards at angles on playmat)

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        return request.results ?? []
    }

    /// Detects cards using Canny edge detection + rectangle finding.
    /// Catches dark cards on dark playmats where color segmentation fails.
    func detectCardsViaEdges(in image: CGImage, maxCards: Int = 20) async -> [CGImage] {
        // Step 1: Enhance contrast and detect edges
        let ciImage = CIImage(cgImage: image)
        let context = CIContext()

        // Boost contrast to amplify subtle card/playmat boundaries
        guard let enhanced = CIFilter(name: "CIColorControls", parameters: [
            kCIInputImageKey: ciImage,
            "inputContrast": 2.0,
            "inputBrightness": 0.1,
            "inputSaturation": 0.0  // grayscale helps edge detection
        ])?.outputImage else { return [] }

        // Apply Canny edge detection
        guard let edges = CIFilter(name: "CICannyEdgeDetector", parameters: [
            kCIInputImageKey: enhanced,
            "inputGaussianSigma": 1.6,
            "inputThresholdLow": 0.02,
            "inputThresholdHigh": 0.06
        ])?.outputImage else { return [] }

        // Convert edge image to CGImage for Vision
        guard let edgeCGImage = context.createCGImage(edges, from: ciImage.extent) else { return [] }

        // Step 2: Find rectangles in the edge image
        let raw = detectRectangles(in: edgeCGImage, maxObservations: maxCards * 3)
        let nmsFiltered = Self.suppressOverlapping(raw, iouThreshold: 0.3)
        let sizeFiltered = Self.filterByConsistentSize(nmsFiltered, minRatio: 0.2)

        // Step 3: Perspective-correct from ORIGINAL image (not edge image)
        var verified: [CGImage] = []
        for obs in sizeFiltered {
            guard let corrected = applyPerspectiveCorrection(to: image, observation: obs) else { continue }
            if await hasText(corrected) {
                verified.append(corrected)
            }
        }
        print("[MTGScanner] Edge detection: \(raw.count) raw → \(nmsFiltered.count) NMS → \(sizeFiltered.count) size → \(verified.count) text-verified")
        return verified
    }

    // MARK: - Saliency-Based Detection

    /// Uses AI saliency (neural network objectness detection) to find cards.
    /// Unlike color/edge-based methods, saliency detects objects by their
    /// internal content (art, text) — not by contrast with the background.
    /// This catches dark cards on dark playmats that other methods miss.
    func detectCardsViaSaliency(in image: CGImage) async -> [CGImage] {
        let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([saliencyRequest])
        } catch {
            print("[MTGScanner] Saliency detection failed: \(error)")
            return []
        }

        guard let result = saliencyRequest.results?.first,
              let salientObjects = result.salientObjects,
              !salientObjects.isEmpty else {
            print("[MTGScanner] Saliency: no salient objects found")
            return []
        }

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let imgArea = imgW * imgH
        var cards: [CGImage] = []

        print("[MTGScanner] Saliency found \(salientObjects.count) salient regions")

        for obj in salientObjects {
            let bbox = obj.boundingBox
            // Convert Vision coords (origin bottom-left) to CGImage coords (origin top-left)
            var cropRect = CGRect(
                x: bbox.minX * imgW,
                y: (1.0 - bbox.maxY) * imgH,
                width: bbox.width * imgW,
                height: bbox.height * imgH
            )

            // Expand by 5% to catch card edges
            cropRect = cropRect.insetBy(
                dx: -cropRect.width * 0.05,
                dy: -cropRect.height * 0.05
            )
            cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))

            // Size filter: each card should be 2-40% of image
            let cropArea = cropRect.width * cropRect.height
            guard cropArea / imgArea > 0.02 && cropArea / imgArea < 0.40 else { continue }

            guard let cropped = image.cropping(to: cropRect.integral) else { continue }

            // Check aspect ratio — is this region roughly card-shaped?
            let aspect = cropRect.width / cropRect.height
            if aspect > 0.50 && aspect < 0.90 {
                // Region is card-shaped, verify it has text (real card)
                if await hasText(cropped) {
                    cards.append(cropped)
                }
            } else if cropRect.width > imgW * 0.4 || cropRect.height > imgH * 0.4 {
                // Large region — might contain multiple cards. Run rectangle
                // detection within it to find individual cards.
                let innerRects = detectRectangles(in: cropped, maxObservations: 10)
                let filtered = Self.suppressOverlapping(innerRects, iouThreshold: 0.3)
                for rect in filtered {
                    if let corrected = applyPerspectiveCorrection(to: cropped, observation: rect) {
                        let correctedArea = CGFloat(corrected.width * corrected.height)
                        // Must be reasonable size relative to original image
                        guard correctedArea / imgArea > 0.02 && correctedArea / imgArea < 0.35 else { continue }
                        if await hasText(corrected) {
                            cards.append(corrected)
                        }
                    }
                }
            }
        }

        print("[MTGScanner] Saliency: \(cards.count) cards after filtering")
        return cards
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
