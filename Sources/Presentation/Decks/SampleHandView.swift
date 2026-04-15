import SwiftUI

/// Sample-hand playtest tool. Resolves the deck's items to real `Card`
/// objects (so we can pull Scryfall image URLs), shuffles the library,
/// draws an opening hand, and supports London mulligan rules + drawing
/// extra cards. Pure playtest — doesn't mutate the deck.
///
/// Two construction modes:
/// - **From a saved `DeckList`** — loads items via the deck repository
///   and resolves each to a `Card` via the card repository. Used by
///   the "My Decks" detail screen.
/// - **From a pre-resolved `[Card]`** — skips resolution entirely. Used
///   by the MTGTop8 deck-detail screen, which has already resolved
///   every card name to its chosen printing.
struct SampleHandView: View {

    // MARK: - Source

    private let title: String
    /// Pre-resolved card list. When set, the view skips the
    /// `DeckList`/repository resolution path and uses these directly.
    private let preloadedCards: [Card]?
    private let deck: DeckList?
    private let deckRepository: DeckListRepository?
    private let cardRepository: CardRepositoryProtocol?

    // MARK: - State

    @State private var allCards: [Card] = []
    @State private var library: [Card] = []
    @State private var hand: [Card] = []
    @State private var mulligans: Int = 0
    @State private var isLoading: Bool = true
    @State private var unresolvedCount: Int = 0
    @State private var previewCard: Card?

    // MARK: - Initializers

    /// Saved-deck initializer (My Decks).
    init(
        deck: DeckList,
        deckRepository: DeckListRepository,
        cardRepository: CardRepositoryProtocol
    ) {
        self.title = "Sample Hand"
        self.preloadedCards = nil
        self.deck = deck
        self.deckRepository = deckRepository
        self.cardRepository = cardRepository
    }

    /// Pre-resolved initializer (MTGTop8 read-only decks). Pass each
    /// card the appropriate number of times — typically you'll expand a
    /// `[(quantity: Int, card: Card)]` mainboard into a flat array.
    init(deckName: String, cards: [Card]) {
        self.title = deckName
        self.preloadedCards = cards
        self.deck = nil
        self.deckRepository = nil
        self.cardRepository = nil
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 110), spacing: 10),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingState
            } else if allCards.isEmpty {
                emptyState
            } else {
                statusBar
                Divider()
                handGrid
                Divider()
                actionBar
            }
        }
        .background(MD3Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ScreenHelpButton(title: "Sample Hand", sections: [
                    HelpSection(icon: "rectangle.stack", title: "What this does",
                                body: "Shuffles the deck and draws an opening hand. Pure simulation — your real deck isn't touched. Useful for testing curve, color consistency, and opening-hand quality before a tournament."),
                    HelpSection(icon: "arrow.uturn.backward", title: "London mulligan",
                                body: "Each Mulligan reshuffles and draws a fresh 7, but the effective hand size shrinks by one per mulligan taken (the 'put cards back' part is implied — we just deal you the smaller hand)."),
                    HelpSection(icon: "plus.rectangle", title: "Draw a card",
                                body: "Pulls the top card off the simulated library into your hand. Useful for sampling early turns."),
                    HelpSection(icon: "arrow.clockwise", title: "Reset",
                                body: "Reshuffles, sets mulligans back to zero, and deals a fresh opening hand."),
                    HelpSection(icon: "hand.tap", title: "Tap a card",
                                body: "Opens a larger preview of the card so you can read it without squinting."),
                ])
            }
        }
        .task {
            await load()
        }
        .sheet(item: $previewCard) { card in
            cardPreviewSheet(card)
        }
    }

    // MARK: - Loading + empty

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Resolving deck cards…")
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Text("No cards to draw")
                .font(MD3Typography.titleLarge)
            Text("Add cards to this deck before testing your opening hand.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                stat(label: "Hand", value: hand.count, color: MD3Theme.primary)
                stat(label: "Library", value: library.count, color: MD3Theme.onSurface)
                if mulligans > 0 {
                    stat(label: "Mulls", value: mulligans, color: .orange)
                }
                Spacer()
            }
            if unresolvedCount > 0 {
                Text("\(unresolvedCount) cards in this deck couldn't be resolved and are excluded from the simulation.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    private func stat(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    // MARK: - Hand grid

    private var handGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(hand.enumerated()), id: \.offset) { _, card in
                    cardImage(card)
                        .onTapGesture { previewCard = card }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func cardImage(_ card: Card) -> some View {
        let url = imageURL(for: card)
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(MD3Theme.outlineVariant, lineWidth: 1)
                    )
            default:
                placeholderImage(card)
            }
        }
    }

    private func placeholderImage(_ card: Card) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(MD3Theme.surfaceVariant)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .overlay(
                Text(card.name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    private func imageURL(for card: Card) -> URL? {
        let urlString = card.imageURIs["normal"]
            ?? card.imageURIs["small"]
            ?? card.imageURIs["large"]
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                mulligan()
            } label: {
                Label("Mulligan", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(mulligans >= 7)

            Button {
                draw()
            } label: {
                Label("Draw", systemImage: "plus.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(library.isEmpty)

            Button {
                reset()
            } label: {
                Label("Reset", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    // MARK: - Card preview sheet

    @ViewBuilder
    private func cardPreviewSheet(_ card: Card) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let url = imageURL(for: card) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            default:
                                placeholderImage(card)
                            }
                        }
                        .frame(maxWidth: 300, maxHeight: 420)
                    }
                    Text(card.name)
                        .font(.headline)
                    Text("\(card.setNameWithYear) · #\(card.collectorNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let oracle = card.oracleText, !oracle.isEmpty {
                        Text(oracle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MD3Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .background(MD3Theme.background)
            .navigationTitle(card.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { previewCard = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Logic

    /// Loads the cards into the simulated library. Either uses the
    /// pre-resolved list (MTGTop8 path) or fetches and resolves the
    /// saved deck's items (My Decks path). Items that can't be
    /// resolved are skipped — the count is surfaced in the status bar.
    private func load() async {
        isLoading = true
        defer { isLoading = false }

        if let preloadedCards {
            allCards = preloadedCards
            unresolvedCount = 0
            if !preloadedCards.isEmpty {
                newHand()
            }
            return
        }

        guard let deck, let deckRepository, let cardRepository else {
            // Both initialization modes failed to provide a source.
            // Should be unreachable but the type system asks.
            return
        }

        let items = (try? deckRepository.fetchItems(deckID: deck.id)) ?? []
        var cards: [Card] = []
        var unresolved = 0
        // Cache by setCode|collectorNumber so duplicates resolve once.
        var cache: [String: Card] = [:]
        for item in items {
            let key = "\(item.setCode)|\(item.collectorNumber)"
            if let cached = cache[key] {
                cards.append(cached)
                continue
            }
            if let card = try? await cardRepository.fetchCard(
                set: item.setCode,
                collectorNumber: item.collectorNumber
            ) {
                cache[key] = card
                cards.append(card)
            } else {
                unresolved += 1
            }
        }
        allCards = cards
        unresolvedCount = unresolved
        if !cards.isEmpty {
            newHand()
        }
    }

    private func newHand() {
        library = allCards.shuffled()
        let handSize = max(0, 7 - mulligans)
        hand = Array(library.prefix(handSize))
        library = Array(library.dropFirst(handSize))
    }

    private func mulligan() {
        mulligans += 1
        newHand()
    }

    private func draw() {
        guard let next = library.first else { return }
        library = Array(library.dropFirst())
        hand.append(next)
    }

    private func reset() {
        mulligans = 0
        newHand()
    }
}
