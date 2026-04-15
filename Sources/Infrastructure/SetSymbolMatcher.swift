import Foundation
import CoreGraphics
import Vision

// MARK: - Set Symbol Matcher

/// Extracts and compares set symbol regions from MTG card images.
///
/// MTG cards display a set symbol icon on the right side of the type line.
/// This matcher locates the type line via OCR scan results, crops the symbol
/// region, and compares symbols between a user's photo and reference images
/// using VNFeaturePrint visual similarity.
struct SetSymbolMatcher: Sendable {

    /// Card type keywords used to identify the type line in OCR results.
    private static let typeKeywords: [String] = [
        "creature", "summon", "artifact", "enchantment",
        "instant", "sorcery", "land", "planeswalker", "tribal",
    ]

    /// Horizontal padding added to the symbol crop region (normalized coords).
    private static let symbolPaddingX: CGFloat = 0.02

    /// Vertical padding added to the symbol crop region (normalized coords).
    private static let symbolPaddingY: CGFloat = 0.01

    /// Width of the symbol region to the right of the type line (normalized).
    private static let symbolWidth: CGFloat = 0.08

    // MARK: - Symbol Region Extraction (User Photo)

    /// Extracts the set symbol region from a user's card photo using OCR results.
    ///
    /// Finds the type line observation by matching against common card type
    /// keywords, then crops the region immediately to the right of the type
    /// line text where the set symbol appears.
    ///
    /// - Parameters:
    ///   - image: The user's card photo as a CGImage.
    ///   - scanResults: OCR scan results from `CardTextRecognizer`.
    /// - Returns: A cropped CGImage of the set symbol region, or nil if no
    ///   type line was found or cropping failed.
    func extractSymbolRegion(from image: CGImage, scanResults: [ScanResult]) -> CGImage? {
        guard let typeLine = findTypeLine(in: scanResults) else {
            return nil
        }

        let box = typeLine.boundingBox

        // Symbol is immediately to the right of the type line text.
        // Vision coordinates: origin at bottom-left, Y increases upward.
        let symbolMinX = box.maxX
        let symbolMaxX = min(symbolMinX + Self.symbolWidth + Self.symbolPaddingX, 1.0)
        let symbolMinY = max(box.minY - Self.symbolPaddingY, 0.0)
        let symbolMaxY = min(box.maxY + Self.symbolPaddingY, 1.0)

        // Convert normalized Vision coords to pixel coords.
        // Vision: origin bottom-left. CGImage: origin top-left.
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        let pixelX = symbolMinX * imageWidth
        let pixelWidth = (symbolMaxX - symbolMinX) * imageWidth
        // Flip Y: CGImage origin is top-left, Vision origin is bottom-left.
        let pixelY = (1.0 - symbolMaxY) * imageHeight
        let pixelHeight = (symbolMaxY - symbolMinY) * imageHeight

        let cropRect = CGRect(
            x: pixelX,
            y: pixelY,
            width: pixelWidth,
            height: pixelHeight
        ).integral

        // Clamp to image bounds
        let clampedRect = cropRect.intersection(
            CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        )

        guard !clampedRect.isEmpty,
              clampedRect.width > 0,
              clampedRect.height > 0 else {
            return nil
        }

        return image.cropping(to: clampedRect)
    }

    // MARK: - Symbol Region Extraction (Reference Image)

    /// Extracts the set symbol region from a standard Scryfall reference card image.
    ///
    /// Reference images have consistent dimensions (~745x1040). The set symbol
    /// is located at approximately x=85-93%, y=55-60% from the top.
    ///
    /// - Parameter image: A Scryfall reference card image.
    /// - Returns: A cropped CGImage of the set symbol region, or nil if
    ///   cropping failed.
    func extractReferenceSymbolRegion(from image: CGImage) -> CGImage? {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        // Reference card symbol position (CGImage coords, origin top-left).
        let pixelX = 0.85 * imageWidth
        let pixelY = 0.55 * imageHeight
        let pixelWidth = 0.08 * imageWidth
        let pixelHeight = 0.05 * imageHeight

        let cropRect = CGRect(
            x: pixelX,
            y: pixelY,
            width: pixelWidth,
            height: pixelHeight
        ).integral

        let clampedRect = cropRect.intersection(
            CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        )

        guard !clampedRect.isEmpty else { return nil }

        return image.cropping(to: clampedRect)
    }

    // MARK: - Symbol Matching

    /// Matches a card's set symbol against candidate reference images.
    ///
    /// Extracts the symbol region from the source photo (using OCR-located
    /// type line), extracts the symbol from each candidate reference image
    /// (using known standard card dimensions), then compares all pairs
    /// using VNFeaturePrint visual similarity.
    ///
    /// - Parameters:
    ///   - sourceImage: The user's card photo.
    ///   - candidateImages: Reference card images with their original indices.
    ///   - scanResults: OCR results from recognizing the source image.
    /// - Returns: The index of the best matching candidate, or nil if matching
    ///   failed (no type line found, no valid crops, or feature print errors).
    func matchBySymbol(
        sourceImage: CGImage,
        candidateImages: [(index: Int, image: CGImage)],
        scanResults: [ScanResult]
    ) async -> Int? {
        guard !candidateImages.isEmpty else { return nil }

        guard let sourceSymbol = extractSymbolRegion(
            from: sourceImage,
            scanResults: scanResults
        ) else {
            return nil
        }

        let imageMatcher = ImageMatcher()

        guard let sourcePrint = await imageMatcher.generateFeaturePrint(
            for: sourceSymbol
        ) else {
            return nil
        }

        var bestIndex: Int?
        var bestDistance: Float = .greatestFiniteMagnitude

        for (index, candidateImage) in candidateImages {
            guard let refSymbol = extractReferenceSymbolRegion(from: candidateImage) else {
                continue
            }

            guard let refPrint = await imageMatcher.generateFeaturePrint(
                for: refSymbol
            ) else {
                continue
            }

            var distance: Float = 0
            do {
                try sourcePrint.computeDistance(&distance, to: refPrint)
                // Use a 5% tolerance to prefer earlier candidates (sorted by priority)
                // Only replace if significantly better, not just marginally
                let threshold = bestDistance * 0.95
                if distance < threshold || bestIndex == nil {
                    bestDistance = distance
                    bestIndex = index
                }
            } catch {
                continue
            }
        }

        return bestIndex
    }

    // MARK: - Symbol Distance (for weighted comparison)

    /// Computes VNFeaturePrint distances between the source symbol and each
    /// candidate's symbol region. Returns an array aligned with `candidateImages`.
    /// Nil entries mean the symbol crop or feature print failed for that candidate.
    func symbolDistances(
        sourceImage: CGImage,
        candidateImages: [(index: Int, image: CGImage)],
        scanResults: [ScanResult]
    ) async -> [Float?] {
        let matcher = ImageMatcher()

        // Try to extract source symbol from OCR-located type line
        let sourceSymbol = extractSymbolRegion(from: sourceImage, scanResults: scanResults)

        // If source symbol extraction fails, try fixed-position fallback
        // (works when the card is well-framed in the photo)
        let symbol: CGImage?
        if let s = sourceSymbol {
            symbol = s
        } else {
            symbol = extractReferenceSymbolRegion(from: sourceImage)
        }

        guard let sourceSymbolImage = symbol,
              let sourcePrint = await matcher.generateFeaturePrint(for: sourceSymbolImage) else {
            return Array(repeating: nil, count: candidateImages.count)
        }

        var distances: [Float?] = []
        for (_, candidateImage) in candidateImages {
            guard let refSymbol = extractReferenceSymbolRegion(from: candidateImage),
                  let refPrint = await matcher.generateFeaturePrint(for: refSymbol) else {
                distances.append(nil)
                continue
            }
            var dist: Float = 0
            do {
                try sourcePrint.computeDistance(&dist, to: refPrint)
                distances.append(dist)
            } catch {
                distances.append(nil)
            }
        }
        return distances
    }

    // MARK: - Private Helpers

    /// Finds the type line among OCR scan results by matching against known
    /// card type keywords.
    private func findTypeLine(in scanResults: [ScanResult]) -> ScanResult? {
        scanResults.first { result in
            let lowercased = result.recognizedText.lowercased()
            return Self.typeKeywords.contains { keyword in
                lowercased.contains(keyword)
            }
        }
    }
}
