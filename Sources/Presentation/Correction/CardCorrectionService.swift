import Foundation
import CoreGraphics

// MARK: - Card Correction Service

/// Handles the correction logic when the user identifies that the app
/// returned the wrong card. Updates the FeaturePrint cache so that
/// future scans of similar card art resolve to the correct card.
///
/// The correction uses the ORIGINAL card image (from the user's photo)
/// to compute the VNFeaturePrint. This means the cached print matches
/// real-world photo conditions, not clean Scryfall reference images.
struct CardCorrectionService: Sendable {

    private let featurePrintCache: FeaturePrintCache
    private let artVariantMatcher: ArtVariantMatcher

    init(
        featurePrintCache: FeaturePrintCache,
        artVariantMatcher: ArtVariantMatcher = ArtVariantMatcher()
    ) {
        self.featurePrintCache = featurePrintCache
        self.artVariantMatcher = artVariantMatcher
    }

    /// Applies a user correction: caches the correct card's art feature print.
    ///
    /// The original card image is used to compute the VNFeaturePrint, so
    /// the cached entry reflects real-world scanning conditions. This makes
    /// future scans of similar cards more accurate.
    ///
    /// - Parameters:
    ///   - correctCard: The card the user selected as the correct identification.
    ///   - originalCardImage: The CGImage from the user's original photo.
    func applyCorrection(
        correctCard: Card,
        originalCardImage: CGImage
    ) async {
        guard let artImage = artVariantMatcher.extractArtRegion(from: originalCardImage) else {
            print("[MTGScanner] Correction failed: could not extract art region")
            return
        }

        // Force-update the cache with the correct card's identity
        // using the original photo's art region as the feature print source
        await featurePrintCache.cacheOrUpdate(
            illustrationID: correctCard.illustrationID ?? "",
            cardName: correctCard.name,
            artImage: artImage
        )
        await featurePrintCache.save()

        print("[MTGScanner] Correction applied: cached '\(correctCard.name)' (\(correctCard.set.name) #\(correctCard.collectorNumber))")
    }
}
