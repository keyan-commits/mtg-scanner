import SwiftUI

// MARK: - Scanned Cards List View

/// Displays a list of identified Magic cards with their images, names, sets, and prices.
struct ScannedCardsListView: View {

    let cards: [Card]
    let repository: CardRepositoryProtocol?
    let deckRepository: DeckListRepository?
    let onCorrection: ((Int, Card) -> Void)?
    let onScanMore: () -> Void

    init(
        cards: [Card],
        repository: CardRepositoryProtocol? = nil,
        deckRepository: DeckListRepository? = nil,
        onCorrection: ((Int, Card) -> Void)? = nil,
        onScanMore: @escaping () -> Void
    ) {
        self.cards = cards
        self.repository = repository
        self.deckRepository = deckRepository
        self.onCorrection = onCorrection
        self.onScanMore = onScanMore
    }

    var body: some View {
        VStack(spacing: 0) {
            if cards.isEmpty {
                emptyState
            } else {
                cardList
            }

            footer
        }
        .background(MD3Theme.background)
        .sheet(item: $correctionItem) { item in
            if let repository {
                CardCorrectionView(
                    repository: repository,
                    currentCard: item.index < cards.count ? cards[item.index] : nil,
                    onCorrection: { correctedCard in
                        correctionItem = nil
                        onCorrection?(item.index, correctedCard)
                    }
                )
            }
        }
    }

    // MARK: - Card List

    @State private var correctionItem: CorrectionItem?
    /// Tracks which cards have been added to the collection in this
    /// session. Shows a checkmark instead of "+" for already-added
    /// cards so the user knows which scanned cards are accounted for.
    @State private var addedToCollection: Set<String> = []
    /// Card being shown in the QuickAddToCollectionSheet.
    @State private var collectionSheetCard: Card?
    /// True after "Add All to Collection" has been tapped — disables
    /// the button and shows confirmation text.
    @State private var didAddAll: Bool = false

    struct CorrectionItem: Identifiable {
        let id = UUID()
        let index: Int
    }

    private var cardList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    ZStack(alignment: .topTrailing) {
                        NavigationLink(value: card) {
                            CardRowView(
                                card: card,
                                onWrongCard: repository != nil ? {
                                    correctionItem = CorrectionItem(index: index)
                                } : nil
                            )
                        }
                        .buttonStyle(.plain)

                        // Quick "Add to Collection" button
                        if deckRepository != nil {
                            Button {
                                collectionSheetCard = card
                            } label: {
                                Image(systemName: addedToCollection.contains(card.scryfallID)
                                      ? "checkmark.circle.fill"
                                      : "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(addedToCollection.contains(card.scryfallID) ? .green : MD3Theme.primary)
                                    .background(Circle().fill(MD3Theme.background).padding(2))
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .accessibilityLabel(addedToCollection.contains(card.scryfallID)
                                                ? "Added to collection"
                                                : "Add to collection")
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationDestination(for: Card.self) { card in
            CardDetailView(
                card: card,
                repository: repository,
                deckRepository: deckRepository,
                onCorrection: { correctedCard in
                    if let index = cards.firstIndex(where: { $0.id == card.id }) {
                        onCorrection?(index, correctedCard)
                    }
                }
            ) {}
        }
        .sheet(item: $collectionSheetCard) { card in
            if let deckRepository {
                QuickAddToCollectionSheet(
                    card: card,
                    deckRepository: deckRepository
                ) {
                    addedToCollection.insert(card.scryfallID)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.minus")
                .font(.system(size: 48))
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            Text("No cards identified")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            Text("Try selecting clearer photos of your cards")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            if !cards.isEmpty {
                totalPriceRow
            }

            // "Add All to Collection" batch button — one tap adds
            // every scanned card to the user's collection with
            // defaults (qty 1, non-foil). ManaBox / TCGplayer pattern.
            if deckRepository != nil && !cards.isEmpty {
                addAllToCollectionButton
            }

            MD3FilledButton("Identify More Cards") {
                onScanMore()
            }
        }
        .padding(16)
        .background(MD3Theme.surface)
    }

    @ViewBuilder
    private var addAllToCollectionButton: some View {
        let unadded = cards.filter { !addedToCollection.contains($0.scryfallID) }
        if didAddAll || unadded.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("All \(cards.count) cards added to collection")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Button {
                addAllToCollection()
            } label: {
                Label("Add All \(unadded.count) to Collection", systemImage: "rectangle.stack.fill.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.primary)
                    .background(MD3Theme.primaryContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func addAllToCollection() {
        guard let deckRepository else { return }
        var addedCount = 0
        for card in cards where !addedToCollection.contains(card.scryfallID) {
            if let _ = try? deckRepository.addToCollection(card: card) {
                addedToCollection.insert(card.scryfallID)
                addedCount += 1
            }
        }
        if addedCount > 0 {
            didAddAll = true
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    private var totalPriceRow: some View {
        HStack {
            Text("Total Value")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onSurface)

            Spacer()

            Text(totalPrice)
                .font(MD3Typography.headlineSmall)
                .foregroundStyle(MD3Theme.primary)
        }
    }

    private var totalPrice: String {
        let total = cards.compactMap { card -> Double? in
            guard let usd = card.prices.usd else { return nil }
            return Double(usd)
        }.reduce(0, +)

        guard total > 0 else { return "—" }
        return String(format: "$%.2f", total)
    }
}

// MARK: - Card Row View

/// A single card row showing thumbnail, name, set, and price.
struct CardRowView: View {

    let card: Card
    var onWrongCard: (() -> Void)?

    var body: some View {
        MD3Card {
            HStack(spacing: 12) {
                cardThumbnail
                cardInfo
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    priceLabel
                    if let onWrongCard {
                        Button {
                            onWrongCard()
                        } label: {
                            Text("Fix")
                                .font(MD3Typography.labelLarge)
                                .foregroundStyle(MD3Theme.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(MD3Theme.outline, lineWidth: 1)
                                )
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private var cardThumbnail: some View {
        Group {
            if let urlString = card.imageURIs["small"],
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        thumbnailPlaceholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 48, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(MD3Theme.surfaceVariant)
            .overlay(
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    private var cardInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.name)
                .font(MD3Typography.titleSmall)
                .foregroundStyle(MD3Theme.onSurface)
                .lineLimit(1)

            Text(card.set.name)
                .font(MD3Typography.bodySmall)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .lineLimit(1)

            Text(card.typeLine)
                .font(MD3Typography.labelSmall)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var priceLabel: some View {
        if let usd = card.prices.usd {
            Text("$\(usd)")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.primary)
        } else {
            Text("—")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }
}
