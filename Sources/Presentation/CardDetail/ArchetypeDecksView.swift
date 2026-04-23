import SwiftUI

/// Shows top decks for a given archetype, fetched from MTGTop8.
/// Tapping a deck navigates to its full decklist.
///
/// Two ways to look up decks:
/// - **Classic source** (`.classic(signatureCard:)`) — used when the
///   archetype came from our hand-curated `ClassicArchetypes` catalog.
///   We don't have an MTGTop8 archetype ID, so the lookup falls back
///   to seeding MTGTop8's card-name search with `signatureCard`.
/// - **Online source** (`.online(archetypeID:formatCode:)`) — used when
///   the archetype was found via `MTGTop8ArchetypeIndex`. Hits MTGTop8's
///   native archetype detail page directly using the numeric ID.
struct ArchetypeDecksView: View {

    let archetype: String
    let format: String
    let source: ArchetypeSource
    /// When set, only decks finishing at or above this placement are
    /// shown (e.g. `10` → top-10 finishes only). Nil means no filter.
    let maxPlacement: Int?
    /// Captures the legacy `formatCode` parameter so the card-detail
    /// call site continues to scope MTGTop8 queries by format. Online
    /// sources carry their own format code in `.online(...)`.
    private let legacyFormatCode: String?

    @State private var decks: [MTGTop8Deck] = []
    @State private var isLoading = true
    @State private var error: String?

    private let service: MTGTop8ServiceProtocol
    /// Forwarded into `MTGTop8DeckDetailView` so the rich detail view
    /// can resolve card names → printings against the local DB.
    private let cardRepository: CardRepositoryProtocol?
    /// Forwarded into `MTGTop8DeckDetailView` and `CardDetailView` —
    /// gives the rich view access to the user's saved-deck repo so
    /// the inner card-detail screens can offer "Add to deck" actions.
    private let deckRepository: DeckListRepository?

    /// Primary initializer — caller chooses which lookup strategy to use
    /// via `source`. Pass `cardRepository` and `deckRepository` so the
    /// resulting deck-detail view can render the rich, tappable list.
    init(
        archetype: String,
        format: String,
        source: ArchetypeSource,
        maxPlacement: Int? = nil,
        cardRepository: CardRepositoryProtocol? = nil,
        deckRepository: DeckListRepository? = nil,
        service: MTGTop8ServiceProtocol = MTGTop8Service()
    ) {
        self.archetype = archetype
        self.format = format
        self.source = source
        self.maxPlacement = maxPlacement
        self.cardRepository = cardRepository
        self.deckRepository = deckRepository
        self.service = service
        self.legacyFormatCode = nil
    }

    /// Convenience initializer for the legacy card-detail call site
    /// (`DeckCompatibilityView`). Constructs a `.classic` source from
    /// the card name and tracks the format code separately for the
    /// MTGTop8 query.
    init(
        archetype: String,
        format: String,
        formatCode: String?,
        cardName: String,
        maxPlacement: Int? = nil,
        cardRepository: CardRepositoryProtocol? = nil,
        deckRepository: DeckListRepository? = nil,
        service: MTGTop8ServiceProtocol = MTGTop8Service()
    ) {
        self.archetype = archetype
        self.format = format
        self.source = .classic(signatureCard: cardName)
        self.maxPlacement = maxPlacement
        self.cardRepository = cardRepository
        self.deckRepository = deckRepository
        self.service = service
        self.legacyFormatCode = formatCode
    }


    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading decks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(MD3Theme.error)
                    Text(error)
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if decks.isEmpty {
                Text("No decks found")
                    .font(MD3Typography.bodyLarge)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(decks) { deck in
                    NavigationLink {
                        // Rich detail view (tappable list, grid,
                        // sample hand, printing-strategy picker).
                        // Both call sites currently pass repos; if
                        // either is nil we render an empty placeholder
                        // so navigation never silently breaks.
                        if let cardRepository, let deckRepository {
                            MTGTop8DeckDetailView(
                                deckID: deck.deckID,
                                deckName: deck.name,
                                player: deck.player,
                                format: format,
                                cardRepository: cardRepository,
                                deckRepository: deckRepository,
                                service: service
                            )
                        } else {
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                Text("Deck repositories not available")
                                    .font(.caption)
                            }
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(MD3Theme.background)
                        }
                    } label: {
                        deckRow(deck)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(archetype)
        .navigationBarTitleDisplayMode(.inline)
        .background(MD3Theme.background)
        .task {
            await loadDecks()
        }
    }

    private func deckRow(_ deck: MTGTop8Deck) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(deck.name)
                    .font(MD3Typography.titleSmall)
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)

                Spacer()

                if !deck.finish.isEmpty {
                    Text("#\(deck.finish)")
                        .font(MD3Typography.labelMedium)
                        .foregroundStyle(MD3Theme.onPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(MD3Theme.primary)
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 6) {
                if !deck.player.isEmpty {
                    Text(deck.player)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.primary)
                }

                if !deck.event.isEmpty {
                    Text("@ \(deck.event)")
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .lineLimit(1)
                }

                if deck.level > 0 {
                    starsView(level: deck.level)
                }

                Spacer()

                if !deck.date.isEmpty {
                    Text(deck.date)
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Renders 1-5 small stars indicating MTGTop8's tournament tier.
    /// 1 = local FNM, 5 = premier event (Pro Tour, Worlds).
    @ViewBuilder
    private func starsView(level: Int) -> some View {
        let clamped = max(0, min(5, level))
        HStack(spacing: 1) {
            ForEach(0..<clamped, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityLabel("\(clamped) star tournament")
    }

    private func loadDecks() async {
        isLoading = true
        do {
            switch source {
            case .classic(let signatureCard):
                decks = try await service.fetchTopDecks(
                    archetype: archetype,
                    format: legacyFormatCode,
                    cardName: signatureCard,
                    maxPlacement: maxPlacement
                )
            case .online(let archetypeID, let formatCode):
                decks = try await service.fetchDecksByArchetypeID(
                    archetypeID,
                    format: formatCode,
                    maxPlacement: maxPlacement
                )
            }
            error = nil
        } catch {
            self.error = "Could not load decks"
        }
        isLoading = false
    }
}
