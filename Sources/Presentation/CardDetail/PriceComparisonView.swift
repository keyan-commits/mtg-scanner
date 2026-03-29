import SwiftUI

// MARK: - Price Comparison View

/// Displays the card's market price from TCGPlayer (via Scryfall) with
/// deep links to check NM prices on Card Kingdom and Hareruya.
struct PriceComparisonView: View {

    let card: Card

    @Environment(\.openURL) private var openURL

    var body: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Market Prices (NM)")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)

                // TCGPlayer — from local DB (instant)
                if let usd = card.prices.usd {
                    priceRow(source: "TCGPlayer", price: "$\(usd)")
                }

                if let usdFoil = card.prices.usdFoil {
                    priceRow(source: "TCGPlayer (Foil)", price: "$\(usdFoil)")
                }

                if card.prices.usd == nil && card.prices.usdFoil == nil {
                    HStack {
                        Text("No pricing data available")
                            .font(MD3Typography.bodyMedium)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        Spacer()
                    }
                }

                Text("Source: TCGPlayer via Scryfall")
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)

                Divider()

                Text("Check NM Prices")
                    .font(MD3Typography.titleSmall)
                    .foregroundStyle(MD3Theme.onSurface)

                HStack(spacing: 12) {
                    storeButton(name: "Card Kingdom") {
                        let setSlug = card.set.name
                            .lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                            .replacingOccurrences(of: "'", with: "")
                            .replacingOccurrences(of: ",", with: "")
                        let cardSlug = card.name
                            .lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                            .replacingOccurrences(of: "'", with: "")
                            .replacingOccurrences(of: ",", with: "")
                        if let url = URL(string: "https://www.cardkingdom.com/mtg/\(setSlug)/\(cardSlug)") {
                            openURL(url)
                        }
                    }

                    storeButton(name: "Hareruya") {
                        let encodedName = card.name
                            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? card.name
                        if let url = URL(string: "https://www.hareruyamtg.com/en/products/search?cardName=\(encodedName)") {
                            openURL(url)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Subviews

    private func priceRow(source: String, price: String) -> some View {
        HStack {
            Text(source)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurface)

            Spacer()

            Text(price)
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.primary)
        }
    }

    private func storeButton(name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(MD3Typography.labelLarge)
                .foregroundStyle(MD3Theme.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(MD3Theme.outline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
