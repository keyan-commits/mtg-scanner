import SwiftUI

/// Renders AI text with **card names** as inline tappable chips.
/// Section headers (**How to Play** etc.) render as bold headlines.
/// Card chips resolve to the deck's actual versions first.
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

    @ViewBuilder
    private func paragraphView(_ paragraph: String) -> some View {
        let segments = parseSegments(paragraph)
        // Use a FlowLayout so chips wrap naturally with the text
        FlowLayout(spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .plain(let str):
                    // Split plain text by spaces to enable wrapping
                    ForEach(Array(str.split(separator: " ", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, word in
                        Text(String(word) + " ")
                            .font(font)
                            .foregroundStyle(MD3Theme.onSurface)
                    }
                case .sectionHeader(let title):
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(MD3Theme.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                case .cardChip(let name):
                    cardChipButton(name)
                }
            }
        }
    }

    private func cardChipButton(_ name: String) -> some View {
        let key = name.lowercased()
        let card = resolvedCards[key] ?? deckCards[key]
        return Button {
            if let card {
                selectedCard = card
                showCardDetail = true
            }
        } label: {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(card != nil ? .white : MD3Theme.onSurfaceVariant)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(card != nil ? MD3Theme.primary : MD3Theme.surfaceVariant)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(card == nil)
        .task { await resolveCard(name) }
    }

    // MARK: - Parsing

    private enum Segment {
        case plain(String)
        case sectionHeader(String)
        case cardChip(String)
    }

    private func parseSegments(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var remaining = text

        while let starRange = remaining.range(of: "**") {
            let before = String(remaining[remaining.startIndex..<starRange.lowerBound])
            if !before.isEmpty { segments.append(.plain(before)) }
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
                    segments.append(.plain(name))
                }
            } else {
                segments.append(.plain("**" + remaining))
                remaining = ""
            }
        }

        if !remaining.isEmpty { segments.append(.plain(remaining)) }
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
        if let card = await resolver.resolve(name: name, strategy: .cheapest) {
            resolvedCards[key] = card
        }
    }
}
