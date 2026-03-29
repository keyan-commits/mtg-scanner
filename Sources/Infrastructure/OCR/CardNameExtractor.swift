import Foundation
import CoreGraphics

// MARK: - Card Name Extractor

/// Extracts the most likely card name from an array of scan results.
///
/// The extraction strategy:
/// 1. Filter out low-confidence results (below 0.5).
/// 2. Sort by vertical position (topmost first, since the card name
///    appears at the top of a Magic card).
/// 3. Take the topmost high-confidence result.
/// 4. Clean the text by removing common OCR artifacts.
/// 5. Return the cleaned name, or nil if no valid name was found.
struct CardNameExtractor: Sendable {

    /// Minimum confidence threshold for considering a result as a potential card name.
    private let minimumConfidence: Double

    /// Minimum character length for a valid card name after cleaning.
    private let minimumNameLength: Int

    /// Creates an extractor with the given thresholds.
    /// - Parameters:
    ///   - minimumConfidence: Minimum confidence to consider a result. Defaults to 0.5.
    ///   - minimumNameLength: Minimum cleaned text length for a valid name. Defaults to 3.
    init(minimumConfidence: Double = 0.5, minimumNameLength: Int = 3) {
        self.minimumConfidence = minimumConfidence
        self.minimumNameLength = minimumNameLength
    }

    /// Extracts the most likely card name from the given scan results.
    ///
    /// - Parameter results: The raw scan results from text recognition.
    /// - Returns: The cleaned card name string, or nil if no valid name was found.
    func extractCardName(from results: [ScanResult]) -> String? {
        let highConfidence = ScanResultFilter.filterByConfidence(
            results,
            minimumConfidence: minimumConfidence
        )

        let sorted = ScanResultSorter.sortByVerticalPosition(highConfidence)

        // Try each result from top to bottom until one passes length check
        for result in sorted {
            let cleaned = cleanText(result.recognizedText)
            if cleaned.count >= minimumNameLength {
                return cleaned
            }
        }

        return nil
    }

    // MARK: - Text Cleaning

    /// Cleans recognized text by removing common OCR artifacts.
    ///
    /// - Trims leading and trailing whitespace and newlines
    /// - Removes leading/trailing pipe characters and other border artifacts
    /// - Replaces underscores with spaces (common OCR misread)
    /// - Collapses multiple consecutive spaces into one
    private func cleanText(_ text: String) -> String {
        var cleaned = text

        // Trim whitespace and newlines
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading/trailing OCR border artifacts (pipes, brackets, asterisks, etc.)
        let borderArtifacts = CharacterSet(charactersIn: "|[]{}~`*#@^")
        cleaned = cleaned.trimmingCharacters(in: borderArtifacts)

        // Trim again after removing artifacts
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Replace underscores with spaces (common OCR artifact)
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")

        // Restore apostrophes: "Mishra s" → "Mishra's", "Sensei s" → "Sensei's"
        // OCR commonly drops apostrophes, leaving "word s" pattern
        let apostrophePattern = #"(\w)\s+s\b"#
        if let regex = try? NSRegularExpression(pattern: apostrophePattern, options: .caseInsensitive) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "$1's")
        }

        // Collapse multiple spaces into single space
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        // Final trim
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
}
