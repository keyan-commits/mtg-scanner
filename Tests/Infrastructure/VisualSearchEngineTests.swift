import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

@Suite("VisualSearchEngine Tests")
struct VisualSearchEngineTests {

    // MARK: - findMatches Tests

    @Test("findMatches returns results sorted by distance")
    func findMatchesSortedByDistance() {
        // Create an image and compute its hash to build an index with known distances
        let queryImage = makeTestImage(width: 100, height: 100, red: 0.5, green: 0.3, blue: 0.8)
        guard let queryHash = PerceptualHash.compute(from: queryImage) else {
            Issue.record("Failed to compute query hash")
            return
        }

        // Build index: one entry identical, one with flipped bits, one very different
        let entries = [
            VisualIndexEntry(illustrationID: "far", cardName: "Far Card", hash: ~queryHash),
            VisualIndexEntry(illustrationID: "exact", cardName: "Exact Card", hash: queryHash),
            VisualIndexEntry(illustrationID: "close", cardName: "Close Card", hash: queryHash ^ 0b111)
        ]
        let engine = VisualSearchEngine(index: entries)
        let matches = engine.findMatches(for: queryImage)

        #expect(matches.count == 3)
        // First result should be the exact match (distance 0)
        #expect(matches[0].entry.illustrationID == "exact")
        #expect(matches[0].distance == 0)
        // Second should be the close match (distance 3)
        #expect(matches[1].entry.illustrationID == "close")
        #expect(matches[1].distance == 3)
        // Third should be the far match
        #expect(matches[2].entry.illustrationID == "far")
        // Verify sorting invariant
        #expect(matches[0].distance <= matches[1].distance)
        #expect(matches[1].distance <= matches[2].distance)
    }

    @Test("bestMatch returns nil when no close match exists")
    func bestMatchReturnsNilWhenNoCloseMatch() {
        let queryImage = makeTestImage(width: 100, height: 100, red: 0.5, green: 0.3, blue: 0.8)
        guard let queryHash = PerceptualHash.compute(from: queryImage) else {
            Issue.record("Failed to compute query hash")
            return
        }

        // All entries are very far from the query hash
        let entries = [
            VisualIndexEntry(illustrationID: "a", cardName: "Card A", hash: ~queryHash),
            VisualIndexEntry(illustrationID: "b", cardName: "Card B", hash: ~queryHash ^ 0xFF)
        ]
        let engine = VisualSearchEngine(index: entries)
        let result = engine.bestMatch(for: queryImage, maxDistance: 15)

        #expect(result == nil)
    }

    @Test("bestMatch returns the closest entry when within threshold")
    func bestMatchReturnsClosestEntry() {
        let queryImage = makeTestImage(width: 100, height: 100, red: 0.5, green: 0.3, blue: 0.8)
        guard let queryHash = PerceptualHash.compute(from: queryImage) else {
            Issue.record("Failed to compute query hash")
            return
        }

        let entries = [
            VisualIndexEntry(illustrationID: "far", cardName: "Far Card", hash: ~queryHash),
            VisualIndexEntry(illustrationID: "match", cardName: "Match Card", hash: queryHash ^ 0b11), // distance 2
            VisualIndexEntry(illustrationID: "close", cardName: "Close Card", hash: queryHash ^ 0b1111) // distance 4
        ]
        let engine = VisualSearchEngine(index: entries)
        let result = engine.bestMatch(for: queryImage, maxDistance: 15)

        #expect(result != nil)
        #expect(result?.illustrationID == "match")
    }

    @Test("Empty index returns no results")
    func emptyIndexReturnsNoResults() {
        let queryImage = makeTestImage(width: 100, height: 100, red: 0.5, green: 0.3, blue: 0.8)
        let engine = VisualSearchEngine(index: [])

        let matches = engine.findMatches(for: queryImage)
        #expect(matches.isEmpty)

        let best = engine.bestMatch(for: queryImage)
        #expect(best == nil)
    }

    // MARK: - Count

    @Test("count returns the number of entries in the index")
    func countReturnsIndexSize() {
        let entries = [
            VisualIndexEntry(illustrationID: "a", cardName: "A", hash: 1),
            VisualIndexEntry(illustrationID: "b", cardName: "B", hash: 2),
            VisualIndexEntry(illustrationID: "c", cardName: "C", hash: 3)
        ]
        let engine = VisualSearchEngine(index: entries)
        #expect(engine.count == 3)
    }

    // MARK: - Sendable Conformance

    @Test("VisualSearchEngine is Sendable")
    func isSendable() {
        let engine: any Sendable = VisualSearchEngine(index: [])
        #expect(engine is VisualSearchEngine)
    }

    // MARK: - maxResults Limit

    @Test("findMatches respects maxResults limit")
    func findMatchesRespectsMaxResults() {
        let queryImage = makeTestImage(width: 100, height: 100, red: 0.5, green: 0.3, blue: 0.8)
        guard let queryHash = PerceptualHash.compute(from: queryImage) else {
            Issue.record("Failed to compute query hash")
            return
        }

        let entries = (0..<10).map { i in
            VisualIndexEntry(illustrationID: "card-\(i)", cardName: "Card \(i)", hash: queryHash ^ UInt64(i))
        }
        let engine = VisualSearchEngine(index: entries)
        let matches = engine.findMatches(for: queryImage, maxResults: 3)

        #expect(matches.count == 3)
    }

    // MARK: - VisualIndexEntry Codable

    @Test("VisualIndexEntry round-trips through JSON encoding and decoding")
    func indexEntryCodable() throws {
        let entry = VisualIndexEntry(illustrationID: "abc-123", cardName: "Lightning Bolt", hash: 0xDEADBEEFCAFE)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(VisualIndexEntry.self, from: data)

        #expect(decoded.illustrationID == entry.illustrationID)
        #expect(decoded.cardName == entry.cardName)
        #expect(decoded.hash == entry.hash)
    }

    // MARK: - Helpers

    /// Creates a test CGImage filled with a gradient and colored rectangles.
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

        context.setFillColor(red: 1.0 - red, green: green, blue: 1.0 - blue, alpha: 1.0)
        context.fill(CGRect(x: width / 10, y: height / 10, width: width / 3, height: height / 4))
        context.setFillColor(red: red, green: 1.0 - green, blue: blue, alpha: 1.0)
        context.fill(CGRect(x: width / 4, y: height / 2, width: width / 3, height: height / 5))

        return context.makeImage()!
    }
}
