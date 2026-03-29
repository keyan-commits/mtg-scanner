import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

@Suite("CopyrightYearExtractor Tests")
struct CopyrightYearExtractorTests {

    let extractor = CopyrightYearExtractor()

    // MARK: - Year Extraction

    @Test("Extracts end year from clean copyright line")
    func extractsEndYearFromCleanCopyright() {
        let results = makeScanResults(bottom: "©1993-1999 Wizards of the Coast, Inc")
        let year = extractor.extractCopyrightEndYear(from: results)
        #expect(year == 1999)
    }

    @Test("Extracts from OCR-mangled copyright, corrects 1009 to 1999")
    func extractsFromOCRMangled() {
        let results = makeScanResults(bottom: "01993-1009 Wizards of the Coast, Inc")
        let year = extractor.extractCopyrightEndYear(from: results)
        #expect(year == 1999)
    }

    @Test("Extracts from another mangled copyright with TM and copyright symbols")
    func extractsFromTMCopyright() {
        let results = makeScanResults(bottom: "™ & © 1993-2002 Wizards of the Coast, Inc.")
        let year = extractor.extractCopyrightEndYear(from: results)
        #expect(year == 2002)
    }

    @Test("Extracts from heavily mangled OCR text, avoids collector number")
    func extractsFromHeavilyMangled() {
        let results = makeScanResults(bottom: "** 8cx. 1905-2002 Wuarde of the Crust, loc 204-350")
        let year = extractor.extractCopyrightEndYear(from: results)
        #expect(year == 2002)
    }

    @Test("Returns nil for text with no copyright pattern")
    func returnsNilForNoCopyright() {
        let results = makeScanResults(bottom: "Wizards of the Coast")
        let year = extractor.extractCopyrightEndYear(from: results)
        #expect(year == nil)
    }

    @Test("Returns nil for empty results")
    func returnsNilForEmpty() {
        let year = extractor.extractCopyrightEndYear(from: [])
        #expect(year == nil)
    }

    @Test("Only looks at bottom portion of scan results")
    func onlyLooksAtBottom() {
        let results = [
            ScanResult(recognizedText: "©1993-2005 Wizards of the Coast", confidence: 0.95,
                       boundingBox: CGRect(x: 0.1, y: 0.85, width: 0.5, height: 0.05)),
            ScanResult(recognizedText: "Creature — Goblin", confidence: 0.90,
                       boundingBox: CGRect(x: 0.1, y: 0.55, width: 0.5, height: 0.05)),
            ScanResult(recognizedText: "©1993-2010 Wizards of the Coast", confidence: 0.80,
                       boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.5, height: 0.03)),
        ]
        let year = extractor.extractCopyrightEndYear(from: results)
        // Only the bottom result (y=0.05) should be considered
        #expect(year == 2010)
    }

    @Test("Handles em-dash between years")
    func handlesEmDash() {
        let results = makeScanResults(bottom: "©1993\u{2014}2015 Wizards of the Coast")
        let year = extractor.extractCopyrightEndYear(from: results)
        #expect(year == 2015)
    }

    @Test("Handles en-dash between years")
    func handlesEnDash() {
        let results = makeScanResults(bottom: "©1993\u{2013}2015 Wizards of the Coast")
        let year = extractor.extractCopyrightEndYear(from: results)
        #expect(year == 2015)
    }

    @Test("Handles OCR reading copyright symbol as C")
    func handlesCopyrightAsC() {
        let results = makeScanResults(bottom: "C1993-2015 Wizards of the Coast")
        let year = extractor.extractCopyrightEndYear(from: results)
        #expect(year == 2015)
    }

    // MARK: - Helpers

    private func makeScanResults(bottom text: String) -> [ScanResult] {
        [
            ScanResult(recognizedText: "Card Name", confidence: 0.95,
                       boundingBox: CGRect(x: 0.1, y: 0.85, width: 0.5, height: 0.05)),
            ScanResult(recognizedText: text, confidence: 0.80,
                       boundingBox: CGRect(x: 0.1, y: 0.05, width: 0.5, height: 0.03)),
        ]
    }
}
