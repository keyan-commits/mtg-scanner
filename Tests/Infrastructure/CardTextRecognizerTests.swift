import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

// MARK: - Mock Text Recognizer

/// A mock implementation of TextRecognizerProtocol for testing purposes.
/// Returns pre-configured scan results without requiring a real camera or image.
struct MockTextRecognizer: TextRecognizerProtocol, Sendable {
    let stubbedResults: [ScanResult]
    let shouldThrow: Bool

    init(results: [ScanResult] = [], shouldThrow: Bool = false) {
        self.stubbedResults = results
        self.shouldThrow = shouldThrow
    }

    func recognizeText(in image: CGImage) async throws -> [ScanResult] {
        if shouldThrow {
            throw TextRecognitionError.noTextFound
        }
        return stubbedResults
    }
}

// MARK: - Tests

@Suite("CardTextRecognizer Tests")
struct CardTextRecognizerTests {

    // MARK: - Protocol Contract

    @Test("TextRecognizerProtocol defines recognizeText method returning [ScanResult]")
    func protocolContractExists() async throws {
        let recognizer: any TextRecognizerProtocol = MockTextRecognizer(results: [])
        let results = try await recognizer.recognizeText(
            in: CardTextRecognizerTests.makeTestImage()
        )
        #expect(results.isEmpty)
    }

    // MARK: - Mock Implementation

    @Test("Mock recognizer returns stubbed results")
    func mockReturnsResults() async throws {
        let expectedResults = [
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.85, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "Instant",
                confidence: 0.90,
                boundingBox: CGRect(x: 0.1, y: 0.70, width: 0.3, height: 0.04)
            )
        ]

        let recognizer = MockTextRecognizer(results: expectedResults)
        let results = try await recognizer.recognizeText(
            in: CardTextRecognizerTests.makeTestImage()
        )

        #expect(results.count == 2)
        #expect(results[0].recognizedText == "Lightning Bolt")
        #expect(results[1].recognizedText == "Instant")
    }

    @Test("Mock recognizer can throw errors")
    func mockThrowsError() async {
        let recognizer = MockTextRecognizer(shouldThrow: true)

        await #expect(throws: TextRecognitionError.self) {
            try await recognizer.recognizeText(
                in: CardTextRecognizerTests.makeTestImage()
            )
        }
    }

    // MARK: - Sorting by Vertical Position

    @Test("Results are sorted by vertical position, topmost first")
    func sortedByVerticalPosition() {
        // In Vision coordinates, higher Y = higher on screen (top of card)
        let results = [
            ScanResult(
                recognizedText: "Rules text here",
                confidence: 0.88,
                boundingBox: CGRect(x: 0.1, y: 0.30, width: 0.8, height: 0.04)
            ),
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "NEO 123",
                confidence: 0.70,
                boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.3, height: 0.03)
            )
        ]

        let sorted = ScanResultSorter.sortByVerticalPosition(results)

        #expect(sorted[0].recognizedText == "Lightning Bolt")
        #expect(sorted[1].recognizedText == "Rules text here")
        #expect(sorted[2].recognizedText == "NEO 123")
    }

    // MARK: - Filtering Logic

    @Test("Low confidence results are filtered out")
    func filtersLowConfidence() {
        let results = [
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "garbled text",
                confidence: 0.30,
                boundingBox: CGRect(x: 0.1, y: 0.50, width: 0.3, height: 0.03)
            ),
            ScanResult(
                recognizedText: "Instant",
                confidence: 0.85,
                boundingBox: CGRect(x: 0.1, y: 0.70, width: 0.3, height: 0.04)
            )
        ]

        let filtered = ScanResultFilter.filterByConfidence(
            results,
            minimumConfidence: 0.5
        )

        #expect(filtered.count == 2)
        #expect(filtered[0].recognizedText == "Lightning Bolt")
        #expect(filtered[1].recognizedText == "Instant")
    }

    @Test("Very short text is filtered out")
    func filtersShortText() {
        let results = [
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "A",
                confidence: 0.90,
                boundingBox: CGRect(x: 0.5, y: 0.80, width: 0.1, height: 0.03)
            ),
            ScanResult(
                recognizedText: "",
                confidence: 0.80,
                boundingBox: CGRect(x: 0.2, y: 0.60, width: 0.1, height: 0.03)
            )
        ]

        let filtered = ScanResultFilter.filterByMinimumLength(
            results,
            minimumLength: 2
        )

        #expect(filtered.count == 1)
        #expect(filtered[0].recognizedText == "Lightning Bolt")
    }

    // MARK: - Multiple Text Regions

    @Test("Recognizes card name vs rules text vs set info by position")
    func multipleTextRegions() {
        // Simulate a full card scan with various text regions
        let results = [
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "{R}",
                confidence: 0.80,
                boundingBox: CGRect(x: 0.7, y: 0.90, width: 0.15, height: 0.05)
            ),
            ScanResult(
                recognizedText: "Instant",
                confidence: 0.90,
                boundingBox: CGRect(x: 0.1, y: 0.55, width: 0.3, height: 0.04)
            ),
            ScanResult(
                recognizedText: "Lightning Bolt deals 3 damage to any target.",
                confidence: 0.88,
                boundingBox: CGRect(x: 0.1, y: 0.40, width: 0.8, height: 0.10)
            ),
            ScanResult(
                recognizedText: "NEO 123/280",
                confidence: 0.70,
                boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.3, height: 0.03)
            )
        ]

        let sorted = ScanResultSorter.sortByVerticalPosition(results)

        // Topmost results should be the card name area
        #expect(sorted[0].recognizedText == "Lightning Bolt")
        #expect(sorted[1].recognizedText == "{R}")

        // Bottom-most should be set info
        #expect(sorted.last?.recognizedText == "NEO 123/280")
    }

    @Test("Combined filter and sort pipeline produces clean results")
    func filterAndSortPipeline() {
        let results = [
            ScanResult(
                recognizedText: "X",
                confidence: 0.90,
                boundingBox: CGRect(x: 0.5, y: 0.95, width: 0.05, height: 0.03)
            ),
            ScanResult(
                recognizedText: "garbled",
                confidence: 0.20,
                boundingBox: CGRect(x: 0.1, y: 0.80, width: 0.3, height: 0.03)
            ),
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "Instant",
                confidence: 0.85,
                boundingBox: CGRect(x: 0.1, y: 0.55, width: 0.3, height: 0.04)
            )
        ]

        // Apply both filters, then sort
        let filtered = ScanResultFilter.filterByConfidence(results, minimumConfidence: 0.5)
        let lengthFiltered = ScanResultFilter.filterByMinimumLength(filtered, minimumLength: 2)
        let sorted = ScanResultSorter.sortByVerticalPosition(lengthFiltered)

        #expect(sorted.count == 2)
        #expect(sorted[0].recognizedText == "Lightning Bolt")
        #expect(sorted[1].recognizedText == "Instant")
    }

    // MARK: - TextRecognitionError

    @Test("TextRecognitionError cases exist")
    func errorCases() {
        let noText = TextRecognitionError.noTextFound
        let processingFailed = TextRecognitionError.imageProcessingFailed

        #expect(noText != processingFailed)
    }

    // MARK: - Helpers

    /// Creates a minimal 1x1 pixel CGImage for testing purposes.
    static func makeTestImage() -> CGImage {
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
        return context.makeImage()!
    }
}
