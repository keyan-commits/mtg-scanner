import SwiftUI

// MARK: - Scanned Cards List View

/// Displays a list of identified Magic cards with their images, names, sets, and prices.
struct ScannedCardsListView: View {

    let cards: [Card]
    let repository: CardRepositoryProtocol?
    let onCorrection: ((Int, Card) -> Void)?
    let onScanMore: () -> Void

    init(
        cards: [Card],
        repository: CardRepositoryProtocol? = nil,
        onCorrection: ((Int, Card) -> Void)? = nil,
        onScanMore: @escaping () -> Void
    ) {
        self.cards = cards
        self.repository = repository
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

    struct CorrectionItem: Identifiable {
        let id = UUID()
        let index: Int
    }

    private var cardList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    NavigationLink(value: card) {
                        CardRowView(
                            card: card,
                            onWrongCard: repository != nil ? {
                                correctionItem = CorrectionItem(index: index)
                            } : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationDestination(for: Card.self) { card in
            CardDetailView(
                card: card,
                repository: repository,
                onCorrection: { correctedCard in
                    if let index = cards.firstIndex(where: { $0.id == card.id }) {
                        onCorrection?(index, correctedCard)
                    }
                }
            ) {}
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

            MD3FilledButton("Identify More Cards") {
                onScanMore()
            }
        }
        .padding(16)
        .background(MD3Theme.surface)
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
