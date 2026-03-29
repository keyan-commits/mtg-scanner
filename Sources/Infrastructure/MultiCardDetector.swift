import Foundation
import CoreGraphics
import Vision

// MARK: - Multi-Card Detector

/// Detects multiple cards in a photo by finding card names via OCR,
/// then cropping card-sized regions around each detected name.
///
/// This approach works for ANY layout (grids, rows, scattered)
/// because it uses text position, not rectangle detection.
struct MultiCardDetector: Sendable {

    private let recognizer: TextRecognizerProtocol
    private let cardDetector: CardDetector

    init(recognizer: TextRecognizerProtocol = VisionTextRecognizer(),
         cardDetector: CardDetector = CardDetector()) {
        self.recognizer = recognizer
        self.cardDetector = cardDetector
    }

    /// Detects and crops all cards in the image.
    /// Returns individual card images, or empty if detection fails.
    func detectAndCropCards(from image: CGImage) async -> [CGImage] {
        // Strategy 1: Find card names via OCR on the full image,
        // then crop card-sized regions around each name
        let ocrCards = await detectByOCR(from: image)
        if ocrCards.count >= 2 {
            return ocrCards
        }

        // Strategy 2: Rectangle detection for single card
        if let single = await cardDetector.detectAndCrop(from: image) {
            return [single]
        }

        return []
    }

    // MARK: - OCR-Based Detection

    private func detectByOCR(from image: CGImage) async -> [CGImage] {
        // Run OCR on the full image to find all text with positions
        guard let scanResults = try? await recognizer.recognizeText(in: image) else {
            return []
        }

        // Find text regions near the TOP of card-sized areas
        // Card names are at the very top of each card (y > 0.85 in Vision coords within each card)
        // In a multi-card image, names appear at various y positions
        // We look for text that could be card names (short, at top of a card-sized region)

        // Group text observations by vertical proximity
        // Each "row" of cards has names at similar y-coordinates
        let candidateNames = findCandidateCardNames(from: scanResults, imageWidth: image.width, imageHeight: image.height)

        if candidateNames.count < 2 {
            return []
        }

        print("[MTGScanner] Multi-card OCR: found \(candidateNames.count) potential card names")

        // Estimate card size from name spacing
        let cardSize = estimateCardSize(from: candidateNames, imageWidth: image.width, imageHeight: image.height)

        // Crop a card-sized region around each name
        return candidateNames.compactMap { nameRegion in
            cropCardRegion(from: image, nameBox: nameRegion, cardSize: cardSize)
        }
    }

    /// Finds text observations that are likely card names.
    /// Card names are typically: short (1-4 words), at the top of the card,
    /// and NOT common rules text.
    private func findCandidateCardNames(from results: [ScanResult], imageWidth: Int, imageHeight: Int) -> [CGRect] {
        let commonRulesText = Set([
            "target", "creature", "damage", "player", "discard",
            "sacrifice", "tap to", "mana pool", "until end", "end of turn",
            "artifact", "enchantment", "sorcery", "instant",
            "assembly worker", "as well"
        ])

        var nameBoxes: [CGRect] = []

        for result in results {
            let text = result.recognizedText.lowercased()
            let wordCount = text.split(separator: " ").count

            // Card names are 1-5 words
            guard wordCount >= 1 && wordCount <= 5 else { continue }

            // Skip common rules text phrases
            let isRulesText = commonRulesText.contains(where: { text.contains($0) })
            if isRulesText { continue }

            // Skip very long text (rules text lines)
            if text.count > 30 { continue }

            // The bounding box in Vision coordinates (origin bottom-left)
            nameBoxes.append(result.boundingBox)
        }

        // Deduplicate: if two names overlap significantly, keep the one with larger bounding box
        return deduplicateBoxes(nameBoxes)
    }

    /// Estimates card dimensions from the positions of detected names.
    private func estimateCardSize(from nameBoxes: [CGRect], imageWidth: Int, imageHeight: Int) -> CGSize {
        // MTG card aspect ratio: 63/88 ≈ 0.716
        // Estimate card width from horizontal spacing between names,
        // or from the image width and number of columns

        // Find distinct x-positions (columns)
        let xCenters = nameBoxes.map { $0.midX }.sorted()
        var columnGap: CGFloat = 0

        if xCenters.count >= 2 {
            // Find minimum gap between adjacent x-centers
            for i in 1..<xCenters.count {
                let gap = xCenters[i] - xCenters[i-1]
                if gap > 0.1 { // At least 10% apart = different column
                    if columnGap == 0 || gap < columnGap {
                        columnGap = gap
                    }
                }
            }
        }

        let cardWidthNorm: CGFloat
        if columnGap > 0 {
            cardWidthNorm = columnGap
        } else {
            // Single column, estimate from image and name width
            let avgNameWidth = nameBoxes.map(\.width).reduce(0, +) / CGFloat(nameBoxes.count)
            cardWidthNorm = avgNameWidth * 1.3 // Card is ~30% wider than the name
        }

        let cardWidth = cardWidthNorm * CGFloat(imageWidth)
        let cardHeight = cardWidth / 0.716 // MTG aspect ratio

        return CGSize(width: cardWidth, height: cardHeight)
    }

    /// Crops a card-sized region centered around a card name position.
    private func cropCardRegion(from image: CGImage, nameBox: CGRect, cardSize: CGSize) -> CGImage? {
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        // Name is at the top of the card (~90% up from bottom in card coordinates)
        // In Vision coords: high Y = top of image
        // The card extends DOWN from the name

        let nameCenterX = nameBox.midX * imgW
        let nameTopY = (1.0 - nameBox.maxY) * imgH // Convert to CGImage coords (origin top-left)

        let cardX = nameCenterX - cardSize.width / 2
        let cardY = nameTopY - cardSize.height * 0.05 // Small margin above name

        let rect = CGRect(
            x: max(0, cardX),
            y: max(0, cardY),
            width: min(cardSize.width, imgW - max(0, cardX)),
            height: min(cardSize.height, imgH - max(0, cardY))
        )

        // Minimum viable size
        guard rect.width > 50 && rect.height > 50 else { return nil }

        return image.cropping(to: rect)
    }

    /// Removes overlapping bounding boxes, keeping larger ones.
    private func deduplicateBoxes(_ boxes: [CGRect]) -> [CGRect] {
        var kept: [CGRect] = []
        let sorted = boxes.sorted { $0.width * $0.height > $1.width * $1.height }

        for box in sorted {
            let overlaps = kept.contains { existing in
                existing.intersects(box) && intersectionArea(existing, box) > 0.3 * min(area(existing), area(box))
            }
            if !overlaps {
                kept.append(box)
            }
        }
        return kept
    }

    private func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
