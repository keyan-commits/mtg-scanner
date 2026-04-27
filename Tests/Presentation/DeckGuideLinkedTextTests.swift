import Testing
import Foundation
@testable import MTGCardScanner

@Suite("DeckGuide buildLinkedText Tests")
struct DeckGuideLinkedTextTests {

    // MARK: - Helpers

    private static let sectionHeaders: Set<String> = [
        "how to play", "key cards & synergies", "matchups to watch",
        "sideboard strategy", "improvement suggestions"
    ]

    /// Replicates buildLinkedText logic from DeckGuideSheet/DeckGuideView
    /// for testable output. Returns segments as (text, isLink, isHeader) tuples.
    struct Segment: Equatable {
        let text: String
        let isCardLink: Bool
        let isSectionHeader: Bool
    }

    private static func parseLinkedSegments(from text: String) -> [Segment] {
        var segments: [Segment] = []
        var remaining = text

        while let starRange = remaining.range(of: "**") {
            let before = String(remaining[remaining.startIndex..<starRange.lowerBound])
            if !before.isEmpty {
                segments.append(Segment(text: before, isCardLink: false, isSectionHeader: false))
            }
            remaining = String(remaining[starRange.upperBound...])

            if let closeRange = remaining.range(of: "**") {
                let name = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                remaining = String(remaining[closeRange.upperBound...])

                if sectionHeaders.contains(name.lowercased()) || name.hasSuffix(":") {
                    segments.append(Segment(text: name, isCardLink: false, isSectionHeader: true))
                } else if name.count >= 3 {
                    segments.append(Segment(text: name, isCardLink: true, isSectionHeader: false))
                } else {
                    segments.append(Segment(text: name, isCardLink: false, isSectionHeader: false))
                }
            } else {
                segments.append(Segment(text: "**" + remaining, isCardLink: false, isSectionHeader: false))
                remaining = ""
            }
        }

        if !remaining.isEmpty {
            segments.append(Segment(text: remaining, isCardLink: false, isSectionHeader: false))
        }
        return segments
    }

    // MARK: - Section Header Detection

    @Test("Detects section headers")
    func detectSectionHeaders() {
        let text = "**How to Play**\nThis deck aims to..."
        let segments = Self.parseLinkedSegments(from: text)
        #expect(segments[0] == Segment(text: "How to Play", isCardLink: false, isSectionHeader: true))
    }

    @Test("Detects header with trailing colon")
    func detectHeaderWithColon() {
        let text = "**Custom Section:** Some content"
        let segments = Self.parseLinkedSegments(from: text)
        #expect(segments[0] == Segment(text: "Custom Section:", isCardLink: false, isSectionHeader: true))
    }

    // MARK: - Card Name Detection

    @Test("Detects card names as links")
    func detectCardNames() {
        let text = "Play **Lightning Bolt** targeting the opponent."
        let segments = Self.parseLinkedSegments(from: text)
        #expect(segments.count == 3)
        #expect(segments[0] == Segment(text: "Play ", isCardLink: false, isSectionHeader: false))
        #expect(segments[1] == Segment(text: "Lightning Bolt", isCardLink: true, isSectionHeader: false))
        #expect(segments[2] == Segment(text: " targeting the opponent.", isCardLink: false, isSectionHeader: false))
    }

    @Test("Short names (< 3 chars) are not card links")
    func shortNamesNotLinks() {
        let text = "Use **Ab** for value."
        let segments = Self.parseLinkedSegments(from: text)
        let abSegment = segments.first { $0.text == "Ab" }
        #expect(abSegment?.isCardLink == false)
    }

    @Test("Three-char names are valid card links")
    func threeCharNamesAreLinks() {
        let text = "Cast **Fog** to survive."
        let segments = Self.parseLinkedSegments(from: text)
        let fogSegment = segments.first { $0.text == "Fog" }
        #expect(fogSegment?.isCardLink == true)
    }

    // MARK: - Edge Cases

    @Test("Unbalanced ** treated as plain text")
    func unbalancedStars() {
        let text = "This has **unclosed bold"
        let segments = Self.parseLinkedSegments(from: text)
        #expect(segments.count == 2)
        #expect(segments[0] == Segment(text: "This has ", isCardLink: false, isSectionHeader: false))
        #expect(segments[1] == Segment(text: "**unclosed bold", isCardLink: false, isSectionHeader: false))
    }

    @Test("Empty text returns empty segments")
    func emptyText() {
        let segments = Self.parseLinkedSegments(from: "")
        #expect(segments.isEmpty)
    }

    @Test("No bold markers returns single plain segment")
    func noBoldMarkers() {
        let text = "Just plain text without any formatting."
        let segments = Self.parseLinkedSegments(from: text)
        #expect(segments.count == 1)
        #expect(segments[0].isCardLink == false)
        #expect(segments[0].isSectionHeader == false)
    }

    @Test("Multiple card names in sequence")
    func multipleCardNames() {
        let text = "**Lightning Bolt** and **Counterspell** are staples."
        let segments = Self.parseLinkedSegments(from: text)
        let cardLinks = segments.filter(\.isCardLink)
        #expect(cardLinks.count == 2)
        #expect(cardLinks[0].text == "Lightning Bolt")
        #expect(cardLinks[1].text == "Counterspell")
    }

    @Test("Mixed headers and card names")
    func mixedContent() {
        let text = """
        **How to Play**
        Cast **Lightning Bolt** early. **Matchups to Watch**
        Watch out for **Teferi, Hero of Dominaria**.
        """
        let segments = Self.parseLinkedSegments(from: text)
        let headers = segments.filter(\.isSectionHeader)
        let cards = segments.filter(\.isCardLink)
        #expect(headers.count == 2)
        #expect(cards.count == 2)
    }

    // MARK: - URL Encoding

    @Test("Card names with special chars generate valid URLs")
    func cardNameURLEncoding() {
        let name = "Teferi, Hero of Dominaria"
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
        let url = URL(string: "mtgcard://\(encoded)")
        #expect(url != nil)
        #expect(url?.scheme == "mtgcard")
        #expect(url?.host?.removingPercentEncoding == name)
    }

    @Test("Card names with apostrophes generate valid URLs")
    func apostropheURLEncoding() {
        let name = "Sensei's Divining Top"
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
        let url = URL(string: "mtgcard://\(encoded)")
        #expect(url != nil)
        #expect(url?.host?.removingPercentEncoding == name)
    }
}
