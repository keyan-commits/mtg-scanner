import Foundation
import CoreGraphics
import Vision

// MARK: - Art Variant Matcher

/// Identifies which art variant a card is by comparing the art region
/// of the user's photo against reference art_crop images from Scryfall.
struct ArtVariantMatcher: Sendable {

    private let imageMatcher: ImageMatcher

    init(imageMatcher: ImageMatcher = ImageMatcher()) {
        self.imageMatcher = imageMatcher
    }

    /// Extracts the art region from a card image.
    ///
    /// The art region is approximately the center of the card:
    /// - Old frame (pre-2003): art spans roughly x: 8-92%, y: 10-52% from top
    /// - Modern frame: art spans roughly x: 6-94%, y: 8-50% from top
    /// We use a generous crop that covers both frame styles.
    ///
    /// - Parameter cardImage: A full card image (ideally perspective-corrected).
    /// - Returns: A cropped CGImage of the art region, or nil if cropping failed.
    func extractArtRegion(from cardImage: CGImage) -> CGImage? {
        let width = cardImage.width
        let height = cardImage.height

        // Art region: center of card, generous crop
        let artX = Int(Double(width) * 0.07)
        let artY = Int(Double(height) * 0.08)  // from top in CGImage coords
        let artW = Int(Double(width) * 0.86)
        let artH = Int(Double(height) * 0.44)

        let artRect = CGRect(x: artX, y: artY, width: artW, height: artH)
        return cardImage.cropping(to: artRect)
    }

    /// Given multiple card variants (same name, same set), determines which
    /// variant best matches the user's card photo by comparing art regions.
    ///
    /// Downloads the art_crop image for each variant from Scryfall, generates
    /// VNFeaturePrint observations, and picks the closest visual match.
    ///
    /// - Parameters:
    ///   - cardImage: The user's card photo (ideally perspective-corrected).
    ///   - variants: Array of Card objects representing different art variants.
    /// - Returns: The best matching Card variant, or nil if comparison fails.
    func matchVariant(cardImage: CGImage, variants: [Card]) async -> Card? {
        guard variants.count > 1 else { return variants.first }

        // Extract art region from user's photo
        guard let userArt = extractArtRegion(from: cardImage) else {
            return variants.first
        }

        // Download art_crop for each variant and compare
        var candidateArts: [(index: Int, image: CGImage)] = []

        for (index, variant) in variants.enumerated() {
            // Prefer art_crop, fall back to normal image
            let urlString = variant.imageURIs["art_crop"] ?? variant.imageURIs["normal"]
            guard let urlString else { continue }

            if let refImage = await imageMatcher.downloadImage(from: urlString) {
                candidateArts.append((index, refImage))
            }
        }

        guard !candidateArts.isEmpty else { return variants.first }

        // Compare user's art against each reference art
        guard let userArtPrint = await imageMatcher.generateFeaturePrint(for: userArt) else {
            return variants.first
        }

        var bestIndex: Int?
        var bestDistance: Float = .greatestFiniteMagnitude

        for (index, refArt) in candidateArts {
            guard let refPrint = await imageMatcher.generateFeaturePrint(for: refArt) else {
                continue
            }

            var distance: Float = 0
            do {
                try userArtPrint.computeDistance(&distance, to: refPrint)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            } catch {
                continue
            }
        }

        guard let bestIndex else { return variants.first }
        return variants[bestIndex]
    }
}
