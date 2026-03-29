import SwiftUI

// MARK: - Price Comparison View

/// Displays market prices from multiple sources (TCGPlayer, Card Kingdom, Hareruya)
/// for a Magic card in Near Mint condition.
struct PriceComparisonView: View {

    let card: Card

    @State private var ckPrice: CardKingdomPrice?
    @State private var hareruyaPrice: HareruyaPrice?
    @State private var isLoadingCK = true
    @State private var isLoadingHareruya = true

    var body: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Market Prices (NM)")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)

                // TCGPlayer — available offline from Scryfall data
                priceRow(
                    source: "TCGPlayer",
                    price: card.prices.usd.map { "$\($0)" },
                    isLoading: false
                )

                // Card Kingdom — loaded on demand
                priceRow(
                    source: "Card Kingdom",
                    price: ckPrice?.formattedRetail,
                    isLoading: isLoadingCK
                )

                // Hareruya — loaded on demand
                priceRow(
                    source: "Hareruya",
                    price: hareruyaPrice?.formattedPrice,
                    isLoading: isLoadingHareruya
                )
            }
            .padding(16)
        }
        .task { await loadPrices() }
    }

    // MARK: - Price Row

    @ViewBuilder
    private func priceRow(source: String, price: String?, isLoading: Bool) -> some View {
        HStack {
            Text(source)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurface)

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let price {
                Text(price)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.primary)
            } else {
                Text("N/A")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        }
    }

    // MARK: - Data Loading

    private func loadPrices() async {
        async let ck: CardKingdomPrice? = {
            let service = CardKingdomPriceService()
            return try? await service.fetchNMPrice(cardName: card.name, setName: card.set.name)
        }()
        async let hr: HareruyaPrice? = {
            let service = HareruyaPriceService()
            return try? await service.fetchNMPrice(cardName: card.name)
        }()

        let ckResult = await ck
        let hrResult = await hr

        ckPrice = ckResult
        isLoadingCK = false
        hareruyaPrice = hrResult
        isLoadingHareruya = false
    }
}
