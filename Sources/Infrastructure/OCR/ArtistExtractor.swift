import Foundation
import CoreGraphics

// MARK: - Artist Extractor

/// Extracts the artist name from OCR scan results by looking for "Illus." prefix
/// in the bottom portion of the card.
struct ArtistExtractor: Sendable {

    private let bottomThreshold: Double

    init(bottomThreshold: Double = 0.35) {
        self.bottomThreshold = bottomThreshold
    }

    /// Extracts the artist name from scan results.
    /// Looks for text containing "Illus" (the artist credit line on MTG cards).
    func extractArtist(from results: [ScanResult]) -> String? {
        let bottomResults = results.filter { $0.boundingBox.origin.y < bottomThreshold }

        for result in bottomResults {
            if let artist = parseArtist(from: result.recognizedText) {
                return artist
            }
        }

        return nil
    }

    /// Parses artist name from text like "Illus. Ben Thompson" or "Ilus Matt Cavotta".
    private func parseArtist(from text: String) -> String? {
        // Match "Illus" (with OCR variants like "Ilus", "IIlus") followed by artist name
        // OCR may read the period as comma, colon, semicolon, or omit it
        let pattern = #"[Il1]{2,4}us[.,;:!]?\s+(.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1 else { return nil }

        var artist = nsText.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip copyright/trademark symbols that OCR may include
        let symbolsToStrip = CharacterSet(charactersIn: "©®™")
        artist = artist.unicodeScalars
            .filter { !symbolsToStrip.contains($0) }
            .map { Character($0) }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard artist.count >= 3 else { return nil }
        return artist
    }
}
