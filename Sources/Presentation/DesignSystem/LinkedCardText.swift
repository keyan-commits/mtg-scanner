import SwiftUI

/// Renders AI text with **card names** as inline tappable chips.
/// Uses AttributedString for proper markdown rendering (bold headers)
/// and extracts card names into a compact chip section after the text.
/// Optimized: single Text view for body, chips only for card names.
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

    /// Render markdown properly (bold headers, bold card names).
    private var attributedText: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// Extract card names from **bold** markers, excluding section headers.
    private var cardNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        let pattern = /\*\*([^*]+)\*\*/
        for match in text.matches(of: pattern) {
            let name = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = name.lowercased()
            guard !sectionHeaders.contains(lower),
                  !name.hasSuffix(":"),
                  name.count >= 3,
                  !seen.contains(lower) else { continue }
            seen.insert(lower)
            names.append(name)
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Single Text view with proper markdown rendering
            Text(attributedText)
                .font(font)
                .foregroundStyle(MD3Theme.onSurface)
                .textSelection(.enabled)

            // Tappable card chips
            if !cardNames.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(cardNames, id: \.self) { name in
                        cardChipButton(name)
                    }
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
