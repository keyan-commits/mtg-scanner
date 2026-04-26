import SwiftUI

/// Renders AI text with **card names** replaced by inline tappable chips.
/// Section headers render as bold headlines. Plain text wraps naturally.
struct LinkedCardText: View {

    let text: String
    let cardRepository: CardRepositoryProtocol?
    let deckCards: [String: Card]
    let font: Font

    @State private var resolvedCards: [String: Card] = [:]
    @State private var selectedCard: Card?
    @State private var showCardDetail: Bool = false

    private let sectionHeaders: Set<String> = [
        "how to play", "key cards & synergies", "matchups to watch",
        "sideboard strategy", "improvement suggestions",
        "competitive playability", "price outlook", "collectibility",
        "recommendation"
    ]

    init(text: String, cardRepository: CardRepositoryProtocol?, deckCards: [String: Card] = [:], font: Font = .body) {
        self.text = text
        self.cardRepository = cardRepository
        self.deckCards = deckCards
        self.font = font
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let paragraphs = text.components(separatedBy: "\n\n")
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    paragraphView(trimmed)
                }
            }
        }
        .navigationDestination(isPresented: $showCardDetail) {
            if let card = selectedCard {
                CardDetailView(
                    card: card,
                    repository: cardRepository,
                    deckRepository: nil,
                    onScanAnother: {}
                )
            }
        }
    }

    // MARK: - Paragraph Rendering

    @ViewBuilder
    private func paragraphView(_ paragraph: String) -> some View {
        let segments = parseSegments(paragraph)
        // Use FlowLayout only if there are chips to inline.
        // Pure text paragraphs render as single Text view.
        let hasChips = segments.contains { if case .cardChip = $0 { return true }; return false }

        if hasChips {
            FlowLayout(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .word(let text):
                        Text(text + " ")
                            .font(font)
                            .foregroundStyle(MD3Theme.onSurface)
                    case .sectionHeader(let title):
                        Text(title + " ")
                            .font(.headline)
                            .foregroundStyle(MD3Theme.onSurface)
                    case .cardChip(let name):
                        cardChipInline(name)
                    }
                }
            }
        } else {
            // No chips — render as single AttributedString Text (fast)
            let md = (try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph)
            Text(md)
                .font(font)
                .foregroundStyle(MD3Theme.onSurface)
        }
    }

    private func cardChipInline(_ name: String) -> some View {
        let key = name.lowercased()
        let card = resolvedCards[key] ?? deckCards[key]
        return Button {
            if let card {
                selectedCard = card
                showCardDetail = true
            }
        } label: {
            Text(name)
                .font(font.bold())
                .foregroundStyle(card != nil ? MD3Theme.primary : MD3Theme.onSurface)
                .underline(card != nil, color: MD3Theme.primary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(card == nil)
        .task { await resolveCard(name) }
    }

    // MARK: - Parsing

    private enum Segment {
        case word(String)
        case sectionHeader(String)
        case cardChip(String)
    }

    /// Parses text into segments. Consecutive plain words are merged into
    /// single `.word` segments to minimize view count (10-20 segments per
    /// paragraph instead of 50-100 individual words).
    private func parseSegments(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var remaining = text

        while let starRange = remaining.range(of: "**") {
            let before = String(remaining[remaining.startIndex..<starRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if !before.isEmpty {
                segments.append(.word(before))
            }
            remaining = String(remaining[starRange.upperBound...])

            if let closeRange = remaining.range(of: "**") {
                let name = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                remaining = String(remaining[closeRange.upperBound...])

                if sectionHeaders.contains(name.lowercased()) || name.hasSuffix(":") {
                    segments.append(.sectionHeader(name.replacingOccurrences(of: ":", with: "")))
                } else if name.count >= 3 {
                    segments.append(.cardChip(name))
                } else {
                    segments.append(.word(name))
                }
            } else {
                segments.append(.word("**" + remaining))
                remaining = ""
            }
        }

        let tail = remaining.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { segments.append(.word(tail)) }
        return segments
    }

    // MARK: - Resolution

    private func resolveCard(_ name: String) async {
        let key = name.lowercased()
        guard resolvedCards[key] == nil else { return }
        if let deckCard = deckCards[key] {
            resolvedCards[key] = deckCard
            return
        }
        guard let repo = cardRepository else { return }
        let resolver = CardResolver(cardRepository: repo)
        if let card = await resolver.resolve(name: name, strategy: .cheapest, allowFuzzyFallback: false) {
            resolvedCards[key] = card
        }
    }
}
