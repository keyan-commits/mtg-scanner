import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

@Suite("SetSymbolMatcher Tests")
struct SetSymbolMatcherTests {

    let matcher = SetSymbolMatcher()

    // MARK: - extractSymbolRegion Tests

    @Test("extractSymbolRegion returns nil for empty scan results")
    func extractSymbolRegionEmptyScanResults() {
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: [])
        #expect(result == nil)
    }

    @Test("extractSymbolRegion returns nil when no type line found")
    func extractSymbolRegionNoTypeLine() {
        let scanResults = [
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.05, y: 0.85, width: 0.6, height: 0.05)
            ),
            ScanResult(
                recognizedText: "Deal 3 damage to any target.",
                confidence: 0.9,
                boundingBox: CGRect(x: 0.05, y: 0.4, width: 0.9, height: 0.05)
            ),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result == nil)
    }

    @Test("extractSymbolRegion returns cropped image when type line is present")
    func extractSymbolRegionWithTypeLine() {
        let scanResults = [
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.05, y: 0.85, width: 0.6, height: 0.05)
            ),
            ScanResult(
                recognizedText: "Instant",
                confidence: 0.9,
                boundingBox: CGRect(x: 0.05, y: 0.55, width: 0.4, height: 0.04)
            ),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
        if let cropped = result {
            #expect(cropped.width > 0)
            #expect(cropped.height > 0)
            #expect(cropped.width < image.width)
            #expect(cropped.height < image.height)
        }
    }

    @Test("Type line detection finds 'Creature'")
    func detectsCreatureTypeLine() {
        let scanResults = [
            makeScanResult(text: "Creature — Goblin", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    @Test("Type line detection finds 'Artifact'")
    func detectsArtifactTypeLine() {
        let scanResults = [
            makeScanResult(text: "Artifact", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    @Test("Type line detection finds 'Land'")
    func detectsLandTypeLine() {
        let scanResults = [
            makeScanResult(text: "Basic Land — Mountain", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    @Test("Type line detection finds 'Instant'")
    func detectsInstantTypeLine() {
        let scanResults = [
            makeScanResult(text: "Instant", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    @Test("Type line detection finds 'Summon'")
    func detectsSummonTypeLine() {
        let scanResults = [
            makeScanResult(text: "Summon Goblin", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    @Test("Type line detection finds 'Enchantment'")
    func detectsEnchantmentTypeLine() {
        let scanResults = [
            makeScanResult(text: "Enchantment — Aura", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    @Test("Type line detection finds 'Sorcery'")
    func detectsSorceryTypeLine() {
        let scanResults = [
            makeScanResult(text: "Sorcery", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    @Test("Type line detection finds 'Planeswalker'")
    func detectsPlaneswalkerTypeLine() {
        let scanResults = [
            makeScanResult(text: "Legendary Planeswalker — Jace", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    @Test("Type line detection finds 'Tribal'")
    func detectsTribalTypeLine() {
        let scanResults = [
            makeScanResult(text: "Tribal Instant — Goblin", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    @Test("Type line detection is case insensitive")
    func detectsTypeLineCaseInsensitive() {
        let scanResults = [
            makeScanResult(text: "CREATURE — GOBLIN", y: 0.55),
        ]
        let image = makeTestImage(width: 400, height: 560)
        let result = matcher.extractSymbolRegion(from: image, scanResults: scanResults)
        #expect(result != nil)
    }

    // MARK: - matchBySymbol Tests

    @Test("matchBySymbol returns nil for empty candidates")
    func matchBySymbolEmptyCandidates() async {
        let image = makeTestImage(width: 400, height: 560)
        let scanResults = [
            makeScanResult(text: "Instant", y: 0.55),
        ]
        let result = await matcher.matchBySymbol(
            sourceImage: image,
            candidateImages: [],
            scanResults: scanResults
        )
        #expect(result == nil)
    }

    @Test("matchBySymbol returns nil when source has no type line")
    func matchBySymbolNoTypeLine() async {
        let source = makeTestImage(width: 400, height: 560)
        let candidate = makeTestImage(width: 400, height: 560)
        let scanResults = [
            ScanResult(
                recognizedText: "Some random text",
                confidence: 0.9,
                boundingBox: CGRect(x: 0.05, y: 0.55, width: 0.4, height: 0.04)
            ),
        ]
        let result = await matcher.matchBySymbol(
            sourceImage: source,
            candidateImages: [(index: 0, image: candidate)],
            scanResults: scanResults
        )
        #expect(result == nil)
    }

    @Test("extractReferenceSymbolRegion crops from standard card dimensions")
    func extractReferenceSymbolRegion() {
        let image = makeTestImage(width: 745, height: 1040)
        let result = matcher.extractReferenceSymbolRegion(from: image)
        #expect(result != nil)
        if let cropped = result {
            #expect(cropped.width > 0)
            #expect(cropped.height > 0)
            #expect(cropped.width < image.width)
            #expect(cropped.height < image.height)
        }
    }

    @Test("SetSymbolMatcher is Sendable")
    func isSendable() {
        let m: any Sendable = SetSymbolMatcher()
        #expect(m is SetSymbolMatcher)
    }

    // MARK: - Helpers

    /// Creates a test CGImage with a gradient background and colored rectangles.
    private func makeTestImage(width: Int, height: Int) -> CGImage {
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

        // Fill with gradient
        for y in 0..<height {
            let r = CGFloat(y) / CGFloat(height)
            let b = 1.0 - r
            context.setFillColor(red: r, green: 0.5, blue: b, alpha: 1.0)
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }

        // Draw rectangles for visual complexity
        context.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0)
        context.fill(CGRect(x: 10, y: 10, width: 80, height: 40))
        context.setFillColor(red: 0.1, green: 0.9, blue: 0.1, alpha: 1.0)
        context.fill(CGRect(x: 50, y: 100, width: 100, height: 60))

        return context.makeImage()!
    }

    /// Creates a ScanResult with common defaults for type line testing.
    private func makeScanResult(text: String, y: CGFloat) -> ScanResult {
        ScanResult(
            recognizedText: text,
            confidence: 0.9,
            boundingBox: CGRect(x: 0.05, y: y, width: 0.4, height: 0.04)
        )
    }
}
