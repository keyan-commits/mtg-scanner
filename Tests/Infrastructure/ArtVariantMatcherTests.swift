import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

@Suite("ArtVariantMatcher Tests")
struct ArtVariantMatcherTests {

    let matcher = ArtVariantMatcher()

    // MARK: - extractArtRegion Tests

    @Test("extractArtRegion returns a cropped image for a valid card image")
    func extractArtRegionValidImage() {
        let image = makeTestImage(width: 745, height: 1040, red: 0.5, green: 0.3, blue: 0.8)
        let result = matcher.extractArtRegion(from: image)
        #expect(result != nil)
        if let cropped = result {
            #expect(cropped.width > 0)
            #expect(cropped.height > 0)
            #expect(cropped.width < image.width)
            #expect(cropped.height < image.height)
        }
    }

    @Test("extractArtRegion returns nil for a tiny image smaller than crop area")
    func extractArtRegionTinyImage() {
        // A 1x1 image: the computed crop rect will have zero or negative dimensions
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let tinyImage = context.makeImage()!

        let result = matcher.extractArtRegion(from: tinyImage)
        // CGImage.cropping returns nil when the rect doesn't intersect or is degenerate
        // For a 1x1 image, the crop rect is (0, 0, 0, 0) which returns nil
        #expect(result == nil)
    }

    // MARK: - matchVariant Tests

    @Test("matchVariant returns the only variant when there is just one")
    func matchVariantSingleVariant() async {
        let image = makeTestImage(width: 400, height: 560, red: 0.5, green: 0.5, blue: 0.5)
        let card = makeTestCard(collectorNumber: "1", artCropURL: nil)

        let result = await matcher.matchVariant(cardImage: image, variants: [card])
        #expect(result == card)
    }

    @Test("matchVariant returns first variant when art extraction fails")
    func matchVariantArtExtractionFails() async {
        // Use a tiny image where art extraction returns nil
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let tinyImage = context.makeImage()!

        let card1 = makeTestCard(collectorNumber: "1", artCropURL: nil)
        let card2 = makeTestCard(collectorNumber: "2", artCropURL: nil)

        let result = await matcher.matchVariant(cardImage: tinyImage, variants: [card1, card2])
        #expect(result == card1)
    }

    @Test("matchVariant returns nil for empty variants array")
    func matchVariantEmpty() async {
        let image = makeTestImage(width: 400, height: 560, red: 0.5, green: 0.5, blue: 0.5)
        let result = await matcher.matchVariant(cardImage: image, variants: [])
        #expect(result == nil)
    }

    @Test("matchVariant returns first variant when no art_crop URLs are available")
    func matchVariantNoArtCropURLs() async {
        let image = makeTestImage(width: 400, height: 560, red: 0.5, green: 0.5, blue: 0.5)
        let card1 = makeTestCard(collectorNumber: "1", artCropURL: nil)
        let card2 = makeTestCard(collectorNumber: "2", artCropURL: nil)

        let result = await matcher.matchVariant(cardImage: image, variants: [card1, card2])
        // With no downloadable URLs, candidateArts will be empty -> returns first
        #expect(result == card1)
    }

    // MARK: - Sendable Conformance

    @Test("ArtVariantMatcher is Sendable")
    func isSendable() {
        let m: any Sendable = ArtVariantMatcher()
        #expect(m is ArtVariantMatcher)
    }

    // MARK: - Art Region Dimensions

    @Test("extractArtRegion crop dimensions match expected proportions")
    func extractArtRegionDimensions() {
        let width = 745
        let height = 1040
        let image = makeTestImage(width: width, height: height, red: 0.3, green: 0.6, blue: 0.1)

        let result = matcher.extractArtRegion(from: image)
        #expect(result != nil)
        if let cropped = result {
            // Expected: x=7% w=86% of 745 -> ~640 wide
            let expectedWidth = Int(Double(width) * 0.86)
            // Expected: y=8% h=44% of 1040 -> ~457 tall
            let expectedHeight = Int(Double(height) * 0.44)

            #expect(cropped.width == expectedWidth)
            #expect(cropped.height == expectedHeight)
        }
    }

    // MARK: - Helpers

    /// Creates a test CGImage filled with a solid color and some visual complexity.
    private func makeTestImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // Fill with gradient based on provided color
        for y in 0..<height {
            let factor = CGFloat(y) / CGFloat(height)
            context.setFillColor(
                red: red * factor,
                green: green * (1.0 - factor),
                blue: blue,
                alpha: 1.0
            )
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }

        // Draw colored rectangles for visual complexity
        context.setFillColor(red: 1.0 - red, green: green, blue: 1.0 - blue, alpha: 1.0)
        context.fill(CGRect(x: 10, y: 10, width: 80, height: 40))
        context.setFillColor(red: red, green: 1.0 - green, blue: blue, alpha: 1.0)
        context.fill(CGRect(x: 50, y: 100, width: 100, height: 60))

        return context.makeImage()!
    }

    /// Creates a test Card with the given collector number and optional art_crop URL.
    private func makeTestCard(collectorNumber: String, artCropURL: String?) -> Card {
        var imageURIs: [String: String] = [:]
        if let artCropURL {
            imageURIs["art_crop"] = artCropURL
        }

        return Card(
            scryfallID: "test-\(collectorNumber)",
            name: "Test Card",
            manaCost: "{1}{R}",
            typeLine: "Instant",
            oracleText: "Test text",
            set: SetInfo(
                code: "tst",
                name: "Test Set",
                setType: "expansion",
                iconSVGURI: nil,
                releasedAt: nil
            ),
            collectorNumber: collectorNumber,
            rarity: .common,
            artist: "Test Artist",
            releasedAt: "2024-01-01",
            borderColor: "black",
            frame: "2015",
            frameEffects: [],
            illustrationID: "illust-\(collectorNumber)",
            edhrecRank: nil,
            prices: CardPrices(usd: nil, usdFoil: nil, eur: nil, eurFoil: nil, tix: nil),
            legalities: FormatLegality([:]),
            imageURIs: imageURIs,
            relatedPrintingsURI: nil
        )
    }
}
