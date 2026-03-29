import Foundation
import CoreGraphics

// MARK: - Collector Info

/// Information extracted from the bottom of an MTG card: collector number and optional set code.
struct CollectorInfo: Sendable, Equatable {
    let collectorNumber: String
    let setCode: String?
}

// MARK: - Collector Info Extractor

/// Extracts collector number and set code from the bottom region of OCR scan results.
///
/// Modern MTG cards (M15 frame, 2014+) print info at the bottom like:
/// `205/274 · ONS · EN · R` or `205/274 ONS EN R`
///
/// Older cards (Exodus through M14, 1998-2014) embed the collector number in the
/// copyright line: `™ & © 1993-2002 Wizards of the Coast, Inc. 205/350`
///
/// OCR commonly misreads the `/` separator as `:`, `-`, `.`, or other characters.
struct CollectorInfoExtractor: Sendable {

    /// The maximum Y value (in Vision coordinates, 0=bottom, 1=top) to consider as "bottom of card".
    private let bottomThreshold: Double

    init(bottomThreshold: Double = 0.35) {
        self.bottomThreshold = bottomThreshold
    }

    /// Extracts collector info from the bottom region of scan results.
    func extractCollectorInfo(from results: [ScanResult]) -> CollectorInfo? {
        let candidates = extractAllCandidates(from: results)
        return candidates.first
    }

    /// Extracts ALL collector info candidates from the bottom of scan results.
    /// Multiple candidates arise from OCR reading the same text differently across cards.
    func extractAllCandidates(from results: [ScanResult]) -> [CollectorInfo] {
        let bottomResults = results
            .filter { $0.boundingBox.origin.y < bottomThreshold }
            .sorted { $0.boundingBox.origin.y < $1.boundingBox.origin.y }

        var candidates: [CollectorInfo] = []
        var seenNumbers: Set<String> = []

        for result in bottomResults {
            if let info = parseCollectorInfo(from: result.recognizedText),
               !info.collectorNumber.isEmpty,
               !seenNumbers.contains(info.collectorNumber) {
                seenNumbers.insert(info.collectorNumber)
                candidates.append(info)
            }
        }

        return candidates
    }

    // MARK: - Parsing

    /// Parses collector number and set code from a text string.
    private func parseCollectorInfo(from text: String) -> CollectorInfo? {
        // Pattern: "205/350", "205:350", "205-350", "205.350", "204-350"
        // OCR commonly misreads `/` as `:`, `-`, `.`, or space
        // Use the LAST match — on old cards the copyright has "1993-2002" before "205/350"
        let numberSeparatorPattern = #"(\d{1,4})\s*[/:\-\.;]\s*(\d{1,4})"#
        if let match = lastMatchPair(pattern: numberSeparatorPattern, in: text),
           !isCopyrightYear(match.0),
           !isPowerToughness(match.0, match.1) {
            let setCode = extractSetCode(from: text)
            return CollectorInfo(collectorNumber: match.0, setCode: setCode)
        }

        // Try M15+ standalone format: "205 ONS" or just set code
        if let setCode = extractSetCode(from: text) {
            let numberBeforeCodePattern = #"(\d{1,4})\s+"# + NSRegularExpression.escapedPattern(for: setCode)
            if let collectorNumber = firstMatch(pattern: numberBeforeCodePattern, in: text, group: 1) {
                return CollectorInfo(collectorNumber: collectorNumber, setCode: setCode)
            }
            return CollectorInfo(collectorNumber: "", setCode: setCode)
        }

        return nil
    }

    /// Extracts a 3-5 letter uppercase set code from text.
    private func extractSetCode(from text: String) -> String? {
        let excludedCodes: Set<String> = [
            "THE", "AND", "FOR", "BUT", "NOT", "ALL", "ARE", "WAS", "HAS",
            "HIS", "HER", "ITS", "INC", "LLC"
        ]

        let setCodePattern = #"\b([A-Z][A-Z0-9]{2,4})\b"#

        guard let regex = try? NSRegularExpression(pattern: setCodePattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            if match.numberOfRanges > 1 {
                let code = nsText.substring(with: match.range(at: 1))
                if code.count >= 3 && code.count <= 5 && !excludedCodes.contains(code) {
                    return code
                }
            }
        }

        return nil
    }

    /// Returns the first regex match group from text.
    private func firstMatch(pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group else { return nil }

        return nsText.substring(with: match.range(at: group))
    }

    /// Returns the LAST regex match as a pair (group1, group2).
    private func lastMatchPair(pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)

        guard let match = matches.last,
              match.numberOfRanges > 2 else { return nil }

        let g1 = nsText.substring(with: match.range(at: 1))
        let g2 = nsText.substring(with: match.range(at: 2))
        return (g1, g2)
    }

    /// Checks if a number pair looks like power/toughness (e.g., "1/1", "3/3", "10/10").
    /// Real collector numbers have a set total > 30 (smallest sets have ~50 cards).
    private func isPowerToughness(_ first: String, _ second: String) -> Bool {
        guard let total = Int(second) else { return false }
        return total <= 30
    }

    /// Checks if a number looks like a copyright year (1993-2030).
    private func isCopyrightYear(_ text: String) -> Bool {
        guard let number = Int(text) else { return false }
        return number >= 1990 && number <= 2030
    }
}
