import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

@Suite("CardNameExtractor Tests")
struct CardNameExtractorTests {

    // MARK: - Clean Card Name at Top

    @Test("Extracts card name from topmost high-confidence result")
    func extractsTopmostCardName() {
        let results = [
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "Instant",
                confidence: 0.88,
                boundingBox: CGRect(x: 0.1, y: 0.55, width: 0.3, height: 0.04)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == "Lightning Bolt")
    }

    @Test("Extracts card name with simple single-word name")
    func extractsSingleWordName() {
        let results = [
            ScanResult(
                recognizedText: "Counterspell",
                confidence: 0.92,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.4, height: 0.05)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == "Counterspell")
    }

    // MARK: - Multiple Text Regions

    @Test("Picks card name over type line and rules text")
    func picksNameOverOtherRegions() {
        let results = [
            ScanResult(
                recognizedText: "Tarmogoyf",
                confidence: 0.93,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.4, height: 0.05)
            ),
            ScanResult(
                recognizedText: "Creature - Lhurgoyf",
                confidence: 0.88,
                boundingBox: CGRect(x: 0.1, y: 0.55, width: 0.5, height: 0.04)
            ),
            ScanResult(
                recognizedText: "Tarmogoyf's power is equal to the number of card types among cards in all graveyards",
                confidence: 0.82,
                boundingBox: CGRect(x: 0.1, y: 0.35, width: 0.8, height: 0.12)
            ),
            ScanResult(
                recognizedText: "MH2 187/303",
                confidence: 0.65,
                boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.3, height: 0.03)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == "Tarmogoyf")
    }

    @Test("Handles card name with special characters")
    func handlesSpecialCharacterNames() {
        let results = [
            ScanResult(
                recognizedText: "Jace, the Mind Sculptor",
                confidence: 0.91,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.6, height: 0.05)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == "Jace, the Mind Sculptor")
    }

    // MARK: - Low Confidence Filtering

    @Test("Skips low confidence topmost result and uses next best")
    func skipsLowConfidenceTopResult() {
        let results = [
            ScanResult(
                recognizedText: "garbled noise",
                confidence: 0.30,
                boundingBox: CGRect(x: 0.1, y: 0.92, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "Lightning Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.88, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "Instant",
                confidence: 0.85,
                boundingBox: CGRect(x: 0.1, y: 0.55, width: 0.3, height: 0.04)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == "Lightning Bolt")
    }

    @Test("Returns nil when all results are low confidence")
    func returnsNilForAllLowConfidence() {
        let results = [
            ScanResult(
                recognizedText: "garbled text 1",
                confidence: 0.20,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            ),
            ScanResult(
                recognizedText: "garbled text 2",
                confidence: 0.15,
                boundingBox: CGRect(x: 0.1, y: 0.70, width: 0.5, height: 0.05)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == nil)
    }

    // MARK: - Empty Results

    @Test("Returns nil for empty results array")
    func returnsNilForEmptyResults() {
        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: [])

        #expect(name == nil)
    }

    // MARK: - OCR Artifact Cleaning

    @Test("Trims leading and trailing whitespace")
    func trimsWhitespace() {
        let results = [
            ScanResult(
                recognizedText: "  Lightning Bolt  ",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == "Lightning Bolt")
    }

    @Test("Collapses multiple internal spaces")
    func collapsesMultipleSpaces() {
        let results = [
            ScanResult(
                recognizedText: "Lightning   Bolt",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == "Lightning Bolt")
    }

    @Test("Removes leading/trailing special OCR artifacts")
    func removesOCRArtifacts() {
        let results = [
            ScanResult(
                recognizedText: "|Lightning Bolt|",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == "Lightning Bolt")
    }

    @Test("Handles underscores as OCR artifacts for spaces")
    func handlesUnderscoreArtifacts() {
        let results = [
            ScanResult(
                recognizedText: "Lightning_Bolt",
                confidence: 0.93,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == "Lightning Bolt")
    }

    @Test("Returns nil when cleaned text is too short")
    func returnsNilWhenCleanedTextTooShort() {
        let results = [
            ScanResult(
                recognizedText: "| |",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.90, width: 0.5, height: 0.05)
            )
        ]

        let extractor = CardNameExtractor()
        let name = extractor.extractCardName(from: results)

        #expect(name == nil)
    }

    // MARK: - Sendable Conformance

    @Test("CardNameExtractor is Sendable")
    func isSendable() {
        let extractor = CardNameExtractor()
        let sendableRef: any Sendable = extractor
        #expect(sendableRef is CardNameExtractor)
    }
}
