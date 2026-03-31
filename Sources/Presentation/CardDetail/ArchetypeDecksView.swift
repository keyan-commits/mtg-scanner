import SwiftUI

/// Shows top decks for a given archetype, fetched from MTGTop8.
/// Tapping a deck navigates to its full decklist.
struct ArchetypeDecksView: View {

    let archetype: String
    let format: String
    let formatCode: String?
    let cardName: String

    @State private var decks: [MTGTop8Deck] = []
    @State private var isLoading = true
    @State private var error: String?

    private let service: MTGTop8ServiceProtocol

    init(archetype: String, format: String, formatCode: String?, cardName: String, service: MTGTop8ServiceProtocol = MTGTop8Service()) {
        self.archetype = archetype
        self.format = format
        self.formatCode = formatCode
        self.cardName = cardName
        self.service = service
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
                    NavigationLink(destination: DecklistDetailView(deckID: deck.deckID, deckName: deck.name, player: deck.player)) {
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

            HStack {
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

    private func loadDecks() async {
        isLoading = true
        do {
            decks = try await service.fetchTopDecks(archetype: archetype, format: formatCode, cardName: cardName)
            error = nil
        } catch {
            self.error = "Could not load decks"
        }
        isLoading = false
    }
}
