import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

/// Integration tests that download real Scryfall art_crop images and verify
/// that VNFeaturePrint can distinguish visually similar but different cards.
///
/// These tests require network access and VNFeaturePrint support.
/// They are automatically skipped when running on environments without
/// network access (e.g., CI without external network) or when VNFeaturePrint
/// is unavailable (some simulator configurations).
@Suite("Art Verification Integration Tests")
struct ArtVerificationIntegrationTests {

    let matcher = ImageMatcher()

    // MARK: - Helpers

    /// Downloads an image, returning nil (and printing a skip message) if network is unavailable.
    private func downloadOrSkip(_ url: String, label: String) async -> CGImage? {
        guard let image = await matcher.downloadImage(from: url) else {
            print("[IntegrationTest] SKIPPED: Could not download \(label) (network unavailable or URL changed)")
            return nil
        }
        return image
    }

    // MARK: - Sliver Misidentification Regression

    /// Plated Sliver and Muscle Sliver are both old-frame green Slivers
    /// with similar art styles. The pHash can confuse them. This test
    /// verifies that VNFeaturePrint distance between their art_crops
    /// exceeds the verification threshold, so the pipeline rejects the
    /// wrong match and tries the next candidate.
    @Test("Plated Sliver vs Muscle Sliver art_crop distance exceeds threshold")
    func platedVsMuscleSliver() async throws {
        // Scryfall art_crop URLs: Plated Sliver (Legions), Muscle Sliver (Tempest)
        let platedSliverArtCrop = "https://cards.scryfall.io/art_crop/front/8/2/82846d31-4981-4ef1-85c3-703569146a84.jpg?1562921399"
        let muscleSliverArtCrop = "https://cards.scryfall.io/art_crop/front/6/0/602a1e1f-4195-48c0-8290-562e7e0db6d8.jpg?1562054245"

        guard let platedArt = await downloadOrSkip(platedSliverArtCrop, label: "Plated Sliver"),
              let muscleArt = await downloadOrSkip(muscleSliverArtCrop, label: "Muscle Sliver") else {
            return // Skip — network unavailable
        }

        guard let distance = await matcher.distance(between: platedArt, and: muscleArt) else {
            print("[IntegrationTest] SKIPPED: VNFeaturePrint unavailable on this platform")
            return
        }

        // The verification threshold in the pipeline is 15.0.
        // These are DIFFERENT arts, so the distance MUST exceed the threshold.
        let verificationThreshold: Float = 15.0
        print("[IntegrationTest] Plated vs Muscle Sliver art distance: \(distance)")
        #expect(
            distance > verificationThreshold,
            "Plated Sliver vs Muscle Sliver art distance (\(distance)) must exceed verification threshold (\(verificationThreshold))"
        )
    }

    /// Same card, same art should be well within threshold (self-comparison).
    @Test("Same card art_crop has zero or near-zero distance")
    func sameCardSelfComparison() async throws {
        let platedSliverArtCrop = "https://cards.scryfall.io/art_crop/front/8/2/82846d31-4981-4ef1-85c3-703569146a84.jpg?1562921399"

        guard let art = await downloadOrSkip(platedSliverArtCrop, label: "Plated Sliver") else {
            return // Skip
        }

        guard let distance = await matcher.distance(between: art, and: art) else {
            print("[IntegrationTest] SKIPPED: VNFeaturePrint unavailable")
            return
        }

        print("[IntegrationTest] Self-comparison distance: \(distance)")
        #expect(distance < 1.0, "Same image should have near-zero distance, got \(distance)")
    }

    /// Two completely different cards should have a large distance.
    @Test("Completely different cards have large art distance")
    func differentCardsLargeDistance() async throws {
        // Plated Sliver (green creature) vs Lightning Bolt (red instant)
        let platedSliverArtCrop = "https://cards.scryfall.io/art_crop/front/8/2/82846d31-4981-4ef1-85c3-703569146a84.jpg?1562921399"
        let lightningBoltArtCrop = "https://cards.scryfall.io/art_crop/front/7/7/77c6fa74-5543-42ac-9ead-0e890b188e99.jpg?1706239968"

        guard let sliverArt = await downloadOrSkip(platedSliverArtCrop, label: "Plated Sliver"),
              let boltArt = await downloadOrSkip(lightningBoltArtCrop, label: "Lightning Bolt") else {
            return // Skip
        }

        guard let distance = await matcher.distance(between: sliverArt, and: boltArt) else {
            print("[IntegrationTest] SKIPPED: VNFeaturePrint unavailable")
            return
        }

        print("[IntegrationTest] Plated Sliver vs Lightning Bolt distance: \(distance)")
        #expect(distance > 20.0, "Completely different cards should have distance > 20, got \(distance)")
    }
}
