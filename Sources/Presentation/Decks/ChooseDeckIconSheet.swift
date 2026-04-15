import SwiftUI

/// Sheet for picking a deck's icon manually. Shows every unique printing
/// in the deck as a thumbnail grid. Tap one → save as the deck's
/// `customSignatureScryfallID`. Tap "Reset to auto" → clear the override
/// and let the algorithm pick again.
struct ChooseDeckIconSheet: View {

    let deck: DeckList
    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol
    let onChanged: () -> Void

    @State private var resolved: [ResolvedThumb] = []
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss

    struct ResolvedThumb: Identifiable {
        let id: String // scryfallID
        let card: Card
        let quantity: Int
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 110), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingState
                } else if resolved.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .background(MD3Theme.background)
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if deck.customSignatureScryfallID != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Reset", role: .destructive) {
                            try? deckRepository.setDeckIcon(deck, scryfallID: nil)
                            onChanged()
                            dismiss()
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Loading cards…")
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Text("No cards to pick from")
                .font(.headline)
            Text("Add cards to this deck to choose an icon.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tap a card to use it as the deck's icon.")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .padding(.horizontal, 16)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(resolved) { entry in
                        thumbnail(entry)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func thumbnail(_ entry: ResolvedThumb) -> some View {
        let isSelected = deck.customSignatureScryfallID == entry.id
        Button {
            try? deckRepository.setDeckIcon(deck, scryfallID: entry.id)
            onChanged()
            dismiss()
        } label: {
            ZStack(alignment: .topLeading) {
                if let urlString = entry.card.imageURIs["normal"]
                                    ?? entry.card.imageURIs["small"]
                                    ?? entry.card.imageURIs["large"],
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(63.0 / 88.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        default:
                            placeholder(entry.card.name)
                        }
                    }
                } else {
                    placeholder(entry.card.name)
                }
                Text("\(entry.quantity)×")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(6)
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(MD3Theme.primary, lineWidth: 3)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(MD3Theme.primary, .white)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: 110)
        }
        .buttonStyle(.plain)
    }

    private func placeholder(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(MD3Theme.surfaceVariant)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .overlay(
                Text(name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // One thumbnail per unique printing. Sort by quantity desc so the
        // cards you have the most of show up first.
        var byScryfallID: [String: (item: PurchaseItem, count: Int)] = [:]
        for item in deck.items {
            if var entry = byScryfallID[item.scryfallID] {
                entry.count += 1
                byScryfallID[item.scryfallID] = entry
            } else {
                byScryfallID[item.scryfallID] = (item: item, count: 1)
            }
        }
        let sorted = byScryfallID.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.item.cardName < $1.item.cardName
        }

        var result: [ResolvedThumb] = []
        for entry in sorted {
            if let card = try? await cardRepository.fetchCard(
                set: entry.item.setCode,
                collectorNumber: entry.item.collectorNumber
            ) {
                result.append(ResolvedThumb(
                    id: entry.item.scryfallID,
                    card: card,
                    quantity: entry.count
                ))
            }
        }
        resolved = result
    }
}
