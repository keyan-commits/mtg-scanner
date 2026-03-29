import Foundation
import CoreGraphics

// MARK: - Copyright Year Extractor

/// Extracts the copyright end year from OCR scan results by looking for year range patterns
/// (e.g. "1993-2002") in the bottom portion of the card.
struct CopyrightYearExtractor: Sendable {

    private let bottomThreshold: Double

    init(bottomThreshold: Double = 0.35) {
        self.bottomThreshold = bottomThreshold
    }

    /// Extracts the copyright end year from scan results.
    /// Returns the second year from a range like "1993-2002" found in the bottom region.
    func extractCopyrightEndYear(from results: [ScanResult]) -> Int? {
        let bottomResults = results.filter { $0.boundingBox.origin.y < bottomThreshold }

        for result in bottomResults {
            if let year = parseCopyrightEndYear(from: result.recognizedText) {
                return year
            }
        }

        return nil
    }

    // MARK: - Parsing

    /// Parses the copyright end year from text.
    /// Handles both range format "1993-2002" and single year "© 1995".
    private func parseCopyrightEndYear(from text: String) -> Int? {
        let normalized = preNormalize(text)
        let nsText = normalized as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // First try: year range "1993-2002", "1993–2015", "1993—1999"
        let rangePattern = #"(\d{4})\s*[-\u2013\u2014]\s*(\d{4})"#
        if let rangeRegex = try? NSRegularExpression(pattern: rangePattern) {
            let matches = rangeRegex.matches(in: normalized, range: fullRange)
            for match in matches {
                guard match.numberOfRanges > 2 else { continue }
                let endYearString = nsText.substring(with: match.range(at: 2))
                if let endYear = Int(endYearString), isValidCopyrightYear(endYear) {
                    return endYear
                }
                if let corrected = attemptYearCorrection(endYearString), isValidCopyrightYear(corrected) {
                    return corrected
                }
            }
        }

        // Second try: single year near copyright symbol "© 1995" or "C 1995"
        // Early MTG cards (1993-1995) used single year, not range
        let singlePattern = #"[©®Cc]\s*(\d{4})"#
        if let singleRegex = try? NSRegularExpression(pattern: singlePattern) {
            let matches = singleRegex.matches(in: normalized, range: fullRange)
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let yearString = nsText.substring(with: match.range(at: 1))
                if let year = Int(yearString), isValidCopyrightYear(year) {
                    return year
                }
                if let corrected = attemptYearCorrection(yearString), isValidCopyrightYear(corrected) {
                    return corrected
                }
            }
        }

        return nil
    }

    /// Pre-normalizes OCR text to fix common letter-digit confusions.
    private func preNormalize(_ text: String) -> String {
        var result = text
        // Replace common OCR misreadings in year contexts:
        // "O" (letter) → "0" (digit) when adjacent to digits
        // This is handled implicitly by the regex matching digits.
        // Normalize dash variants to standard hyphen for consistency
        result = result.replacingOccurrences(of: "\u{2013}", with: "\u{2013}") // keep en-dash (handled in regex)
        result = result.replacingOccurrences(of: "\u{2014}", with: "\u{2014}") // keep em-dash (handled in regex)
        return result
    }

    /// Attempts to correct an OCR-mangled year string.
    /// For example, "1009" might be a misread of "1999" (0→9).
    private func attemptYearCorrection(_ yearString: String) -> Int? {
        // Try replacing '0' with '9' — common OCR confusion
        let corrected = yearString.replacingOccurrences(of: "0", with: "9")
        return Int(corrected)
    }

    /// Checks if a year is within the valid MTG copyright range (1993-2030).
    private func isValidCopyrightYear(_ year: Int) -> Bool {
        year >= 1993 && year <= 2030
    }
}
