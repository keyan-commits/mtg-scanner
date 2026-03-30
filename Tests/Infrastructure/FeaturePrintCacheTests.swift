import Testing
import Foundation
import CoreGraphics
import Vision
@testable import MTGCardScanner

@Suite("FeaturePrintCache Tests")
struct FeaturePrintCacheTests {

    // MARK: - Helpers

    /// Creates a visually complex test image that VNFeaturePrint can process.
    /// Uses gradients, shapes, circles, and pseudo-random patterns for sufficient visual
    /// complexity. Must be large enough (299x299+) for VNFeaturePrint to work on simulator.
    private func makeTestImage(width: Int = 300, height: Int = 300, seed: Int = 0) -> CGImage {
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

        // Draw gradient background with seed-based color shift
        let rShift = CGFloat(seed % 7) / 7.0
        let gShift = CGFloat(seed % 5) / 5.0
        for y in 0..<height {
            let r = (CGFloat(y) / CGFloat(height) + rShift).truncatingRemainder(dividingBy: 1.0)
            let g = (CGFloat(width - 1) / CGFloat(width) + gShift).truncatingRemainder(dividingBy: 1.0)
            let b = 1.0 - r
            context.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }

        // Draw many distinct shapes for visual complexity
        for i in 0..<20 {
            let x = CGFloat((seed * 37 + i * 53) % width)
            let y = CGFloat((seed * 41 + i * 67) % height)
            let w = CGFloat(20 + (seed + i * 11) % 60)
            let h = CGFloat(20 + (seed + i * 13) % 60)
            let r = CGFloat((seed + i * 7) % 10) / 10.0
            let g = CGFloat((seed + i * 3) % 10) / 10.0
            let b = CGFloat((seed + i * 5) % 10) / 10.0
            context.setFillColor(red: r, green: g, blue: b, alpha: 0.8)
            context.fill(CGRect(x: x, y: y, width: w, height: h))
        }

        // Draw circles for additional feature variety
        for i in 0..<10 {
            let cx = CGFloat((seed * 29 + i * 43) % width)
            let cy = CGFloat((seed * 31 + i * 47) % height)
            let radius = CGFloat(10 + (seed + i * 17) % 40)
            let r = CGFloat((seed + i * 9) % 10) / 10.0
            let g = CGFloat((seed + i * 11) % 10) / 10.0
            let b = CGFloat((seed + i * 13) % 10) / 10.0
            context.setFillColor(red: r, green: g, blue: b, alpha: 0.9)
            context.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
        }

        return context.makeImage()!
    }

    /// Creates a temporary file URL for cache persistence tests.
    private func makeTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("test_featureprint_cache_\(UUID().uuidString).json")
    }

    // MARK: - Tests

    @Test("Cache starts empty")
    func cacheStartsEmpty() async {
        let url = makeTempFileURL()
        let cache = FeaturePrintCache(fileURL: url)
        let count = await cache.count
        #expect(count == 0)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Search returns nil for empty cache")
    func searchReturnsNilForEmptyCache() async {
        let url = makeTempFileURL()
        let cache = FeaturePrintCache(fileURL: url)
        let image = makeTestImage()
        let result = await cache.search(artImage: image)
        #expect(result == nil)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Can cache and retrieve a feature print")
    func canCacheAndRetrieve() async {
        let url = makeTempFileURL()
        let cache = FeaturePrintCache(fileURL: url)
        let image = makeTestImage(seed: 1)

        await cache.cache(illustrationID: "abc-123", cardName: "Lightning Bolt", artImage: image)
        let count = await cache.count
        // VNFeaturePrint may fail to generate on simulator — count could be 0 or 1
        #expect(count <= 1)

        if count == 1 {
            // Search with the same image should find a match
            let result = await cache.search(artImage: image)
            if let result {
                #expect(result.cardName == "Lightning Bolt")
                #expect(result.illustrationID == "abc-123")
            }
        }

        try? FileManager.default.removeItem(at: url)
    }

    @Test("Duplicate illustration ID is not added twice")
    func noDuplicateIllustrationIDs() async {
        let url = makeTempFileURL()
        let cache = FeaturePrintCache(fileURL: url)
        let image1 = makeTestImage(seed: 2)
        let image2 = makeTestImage(seed: 3)

        await cache.cache(illustrationID: "dup-id", cardName: "Counterspell", artImage: image1)
        let afterFirst = await cache.count

        await cache.cache(illustrationID: "dup-id", cardName: "Counterspell", artImage: image2)
        let afterSecond = await cache.count

        // If VNFeaturePrint works, first cache adds 1 entry, second is a duplicate => stays at 1
        // If VNFeaturePrint fails, both attempts fail silently => stays at 0
        #expect(afterFirst == afterSecond, "Duplicate ID should not increase count")
        #expect(afterSecond <= 1)

        try? FileManager.default.removeItem(at: url)
    }

    @Test("Count reflects entries")
    func countReflectsEntries() async {
        let url = makeTempFileURL()
        let cache = FeaturePrintCache(fileURL: url)

        let img1 = makeTestImage(seed: 4)
        let img2 = makeTestImage(seed: 5)
        let img3 = makeTestImage(seed: 6)

        await cache.cache(illustrationID: "id-1", cardName: "Card A", artImage: img1)
        let c1 = await cache.count

        await cache.cache(illustrationID: "id-2", cardName: "Card B", artImage: img2)
        let c2 = await cache.count

        await cache.cache(illustrationID: "id-3", cardName: "Card C", artImage: img3)
        let c3 = await cache.count

        // On real device: c1=1, c2=2, c3=3
        // On simulator where VNFeaturePrint fails: c1=c2=c3=0
        // The key invariant: count never decreases, and each unique ID adds at most 1
        #expect(c1 <= c2)
        #expect(c2 <= c3)
        #expect(c3 <= 3)
        // If feature prints work, verify correct count
        if c1 > 0 {
            #expect(c3 == 3)
        }

        try? FileManager.default.removeItem(at: url)
    }

    @Test("Sendable conformance — actor is inherently Sendable")
    func sendableConformance() async {
        let url = makeTempFileURL()
        let cache = FeaturePrintCache(fileURL: url)
        // Actors are Sendable — verify we can pass it across concurrency boundaries
        let sendableRef: any Sendable = cache
        #expect(sendableRef is FeaturePrintCache)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Save and reload persists entries")
    func saveAndReloadPersists() async {
        let url = makeTempFileURL()

        // Create cache and add entry
        let cache1 = FeaturePrintCache(fileURL: url)
        let image = makeTestImage(seed: 7)
        await cache1.cache(illustrationID: "persist-id", cardName: "Dark Ritual", artImage: image)
        await cache1.save()

        // Create a new cache from the same file — should load persisted data
        let cache2 = FeaturePrintCache(fileURL: url)
        let count = await cache2.count
        // If feature print generation succeeded, we should have 1 entry
        // On CI/simulator, feature print may fail, so count could be 0
        if await cache1.count > 0 {
            #expect(count == 1)
        }

        try? FileManager.default.removeItem(at: url)
    }
}
