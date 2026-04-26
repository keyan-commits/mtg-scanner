import SwiftUI

/// Renders AI text with **bold card names** properly formatted.
/// Bold card names are extracted and shown as tappable chips after
/// the text, resolving to the deck's actual card versions first.
struct LinkedCardText: View {

    let text: String
    let cardRepository: CardRepositoryProtocol?
    /// Cards from the deck keyed by lowercased name — used to resolve
    /// the correct version (not cheapest global printing).
    let deckCards: [String: Card]
    let font: Font

    @State private var resolvedCards: [String: Card] = [:]
    @State private var selectedCard: Card?
    @State private var showCardDetail: Bool = false

    init(text: String, cardRepository: CardRepositoryProtocol?, deckCards: [String: Card] = [:], font: Font = .body) {
        self.text = text
        self.cardRepository = cardRepository
        self.deckCards = deckCards
        self.font = font
    }

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// Extract card names from **bold** markers, excluding section headers.
    private var cardNames: [String] {
        let headers: Set<String> = [
            "how to play", "key cards & synergies", "matchups to watch",
            "sideboard strategy", "improvement suggestions",
            "competitive playability", "price outlook", "collectibility"
        ]
        var names: [String] = []
        var seen = Set<String>()
        let pattern = /\*\*([^*]+)\*\*/
        for match in text.matches(of: pattern) {
            let name = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = name.lowercased()
            guard !headers.contains(lower),
                  !name.contains(":"),
                  name.count >= 3,
                  !seen.contains(lower) else { continue }
            seen.insert(lower)
            names.append(name)
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(attributedText)
                .font(font)
                .foregroundStyle(MD3Theme.onSurface)
                .textSelection(.enabled)

            // Tappable card chips inline
            if !cardNames.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(cardNames, id: \.self) { name in
                        cardChip(name)
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

    private func cardChip(_ name: String) -> some View {
        let key = name.lowercased()
        let isResolved = resolvedCards[key] != nil || deckCards[key] != nil
        return Button {
            if let card = resolvedCards[key] ?? deckCards[key] {
                selectedCard = card
                showCardDetail = true
            }
        } label: {
            Text(name)
                .font(.caption.weight(.medium))
                .foregroundStyle(isResolved ? .white : MD3Theme.onSurfaceVariant)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isResolved ? MD3Theme.primary : MD3Theme.surfaceVariant)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isResolved)
        .task { await resolveCard(name) }
    }

    private func resolveCard(_ name: String) async {
        let key = name.lowercased()
        guard resolvedCards[key] == nil else { return }
        // Deck cards first (correct version)
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
