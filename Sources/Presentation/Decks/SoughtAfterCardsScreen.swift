import SwiftUI

/// Dedicated full-screen view for "Most Sought-After Cards" reached
/// from the home page section header. Shows:
/// - **Overall** top 10 across every cached archetype + format
/// - **Per-format** top 10 for every format that has any data
///
/// Each row is tappable and navigates to `CardDetailView` for the
/// resolved card. Card image and printing follow the user's Default
/// Printing setting via `CardResolver`.
struct SoughtAfterCardsScreen: View {

    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository
    private let service: SoughtAfterCardsServiceProtocol

    @State private var sections: [FormatTopCards] = []
    @State private var resolved: [String: Card] = [:]
    @State private var isLoading: Bool = true

    init(
        cardRepository: CardRepositoryProtocol,
        deckRepository: DeckListRepository,
        service: SoughtAfterCardsServiceProtocol = SoughtAfterCardsService()
    ) {
        self.cardRepository = cardRepository
        self.deckRepository = deckRepository
        self.service = service
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                if isLoading && sections.isEmpty {
                    loadingView
                } else if sections.isEmpty {
                    emptyView
                } else {
                    introBlurb
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
                Color.clear.frame(height: 24)
            }
            .padding(16)
        }
        .background(MD3Theme.background)
        .navigationTitle("Most Sought-After")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    // MARK: - Empty / loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading global ranking…")
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Text("No data yet")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("Browse a major archetype or wait for the home page warm-up to finish.")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    private var introBlurb: some View {
        Text("Cards that show up across the most cached archetypes. Overall combines every format; per-format sections rank cards within decks tagged for that specific format.")
            .font(.caption2)
            .foregroundStyle(MD3Theme.onSurfaceVariant)
    }

    // MARK: - Section

    private func sectionView(_ section: FormatTopCards) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.formatName.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.primary)
                Spacer()
                Text("\(section.cards.count)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            if section.cards.isEmpty {
                Text("No cards yet for this format.")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MD3Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(section.cards.enumerated()), id: \.element.id) { idx, card in
                        cardRow(rank: idx + 1, card: card, sectionCards: section.cards)
                        if idx < section.cards.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .background(MD3Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func cardRow(rank: Int, card: SoughtAfterCard, sectionCards: [SoughtAfterCard] = []) -> some View {
        if let resolvedCard = resolved[card.cardName] {
            NavigationLink {
                let allResolved = sectionCards.compactMap { resolved[$0.cardName] }
                if allResolved.count > 1,
                   let pos = allResolved.firstIndex(where: { $0.scryfallID == resolvedCard.scryfallID }) {
                    CardListPagerView(
                        cards: allResolved,
                        initialIndex: pos,
                        cardRepository: cardRepository,
                        deckRepository: deckRepository
                    )
                } else {
                    CardDetailView(
                        card: resolvedCard,
                        repository: cardRepository,
                        deckRepository: deckRepository,
                        onScanAnother: {}
                    )
                }
            } label: {
                cardRowContent(rank: rank, card: card, resolved: resolvedCard)
            }
            .buttonStyle(.plain)
        } else {
            cardRowContent(rank: rank, card: card, resolved: nil)
                .task { await resolveCard(name: card.cardName) }
        }
    }

    private func cardRowContent(rank: Int, card: SoughtAfterCard, resolved: Card?) -> some View {
        HStack(spacing: 12) {
            Text("#\(rank)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(MD3Theme.primary)
                .frame(width: 32, alignment: .trailing)

            // Tiny art-crop thumb
            if let resolved,
               let urlString = resolved.imageURIs["art_crop"]
                   ?? resolved.imageURIs["small"]
                   ?? resolved.imageURIs["normal"],
               let url = URL(string: urlString) {
                CachedPhaseImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        thumbPlaceholder
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                thumbPlaceholder
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.cardName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                Text("in \(card.archetypeCount) archetype\(card.archetypeCount == 1 ? "" : "s") · \(card.totalCopies) copies")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            if resolved != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private var thumbPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(MD3Theme.surfaceVariant)
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: "rectangle.stack")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        sections = await service.topCardsByFormat(limit: 10)
        // Fall back to hardcoded staples when aggregation cache is empty
        if sections.isEmpty {
            sections = service.seedTopCardsByFormat(limit: 10)
        }
        // Don't bulk-resolve here — every CardResolver.resolve call
        // hops to the @MainActor-isolated DatabaseManager and 100+
        // parallel calls would freeze the UI for seconds. Each row's
        // own `.task` resolves itself when it scrolls into view, so
        // the work is deferred and bounded by what's actually visible.
    }

    private func resolveCard(name: String) async {
        guard resolved[name] == nil else { return }
        let resolver = CardResolver(cardRepository: cardRepository)
        // `allowFuzzyFallback: false` keeps scroll latency tight —
        // the Levenshtein walk over 50K records would freeze the
        // main actor for ~100ms per miss otherwise. Sought-after
        // names come from MTGTop8 aggregations which are virtually
        // always exact matches; fuzzy is only useful in deck-detail
        // contexts where the user explicitly wants the lookup.
        if let card = await resolver.resolve(name: name, allowFuzzyFallback: false) {
            resolved[name] = card
        }
    }
}
