import SwiftUI

// MARK: - Price Comparison View

/// Displays the card's market price from TCGPlayer (via Scryfall) with
/// deep links to check NM prices on Card Kingdom and Hareruya.
struct PriceComparisonView: View {

    let card: Card

    @Environment(\.openURL) private var openURL
    @Bindable private var currencyService = CurrencyService.shared
    @State private var priceHistory: MTGStocksPriceHistory?
    @State private var mtgStocksCard: MTGStocksCard?
    @State private var mtgStocksID: Int?
    @State private var historyTimeRange: PriceSparklineView.TimeRange = .year
    @State private var isLoadingHistory: Bool = false

    var body: some View {
        let preferred = LocalCurrency.current
        let marketUSD = card.prices.usd.flatMap(Double.init)
        let foilUSD = card.prices.usdFoil.flatMap(Double.init)
        let eurAmount = card.prices.eur.flatMap(Double.init)
        MD3Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Market Prices (NM)")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)

                // TCGPlayer Low / Market / High range.
                // Uses real data from MTGStocks when available,
                // otherwise estimates from Scryfall market price.
                if let rangeUSD = marketUSD ?? foilUSD {
                    if let detail = mtgStocksCard,
                       let realLow = detail.tcgLow,
                       let realMarket = detail.tcgMarket,
                       let realHigh = detail.tcgHigh {
                        tcgRangeReal(low: realLow, market: realMarket, high: realHigh, preferred: preferred)
                    } else {
                        tcgRange(marketUSD: rangeUSD, preferred: preferred)
                    }
                }

                if marketUSD != nil || foilUSD != nil || eurAmount != nil {
                    Divider()
                }

                // Other authentic tiers from Scryfall (foil, EUR, MTGO).
                if let usdString = card.prices.usd, let usd = Double(usdString) {
                    priceRow(
                        source: "TCGPlayer Market",
                        primary: formatLocal(usd, currency: preferred),
                        secondary: preferred == "USD" ? nil : "$\(usdString) USD"
                    )
                }

                if let usdFoilString = card.prices.usdFoil, let usdFoil = Double(usdFoilString) {
                    priceRow(
                        source: "TCGPlayer (Foil)",
                        primary: formatLocal(usdFoil, currency: preferred),
                        secondary: preferred == "USD" ? nil : "$\(usdFoilString) USD"
                    )
                }

                if let eurString = card.prices.eur, let eurValue = Double(eurString) {
                    let displayCurrency = preferred == "EUR" ? "EUR" : preferred
                    let converted = displayCurrency == "EUR"
                        ? eurValue
                        : currencyService.convert(eurValue / (currencyService.convert(1, to: "EUR") ?? 1), to: preferred) ?? eurValue
                    priceRow(
                        source: "Cardmarket (EUR)",
                        primary: LocalCurrency.format(converted, currency: displayCurrency),
                        secondary: preferred == "EUR" ? nil : "€\(eurString)"
                    )
                }

                if card.prices.usd == nil && card.prices.usdFoil == nil {
                    HStack {
                        Text("No pricing data available")
                            .font(MD3Typography.bodyMedium)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        Spacer()
                    }
                }

                Text(sourceLabel(preferred: preferred))
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)

                Divider()

                Text("Check NM Prices")
                    .font(MD3Typography.titleSmall)
                    .foregroundStyle(MD3Theme.onSurface)

                HStack(spacing: 12) {
                    storeButton(name: "Card Kingdom") {
                        let encodedName = card.name
                            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? card.name
                        if let url = URL(string: "https://www.cardkingdom.com/catalog/search?search=header&filter%5Bname%5D=\(encodedName)") {
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

                // MARK: - Price History Chart (MTGStocks)

                if isLoadingHistory {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading price data…")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                    .padding(.top, 4)
                } else if mtgStocksCard != nil || priceHistory != nil {
                    Divider()

                    // Price History Chart
                    if let history = priceHistory, !history.averagePrices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Price History")
                                    .font(MD3Typography.titleSmall)
                                    .foregroundStyle(MD3Theme.onSurface)
                                Spacer()
                                Picker("", selection: $historyTimeRange) {
                                    ForEach(PriceSparklineView.TimeRange.allCases) { range in
                                        Text(range.rawValue).tag(range)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }

                            PriceSparklineView(
                                dataPoints: history.averagePrices,
                                timeRange: historyTimeRange
                            )
                        }
                    }

                    // ATH/ATL + MTGStocks link
                    if let detail = mtgStocksCard {
                        HStack(spacing: 16) {
                            if let ath = detail.allTimeHigh?.avg {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("ATH")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "$%.2f", ath))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.green)
                                }
                            }
                            if let atl = detail.allTimeLow?.avg {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("ATL")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(String(format: "$%.2f", atl))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            if let id = mtgStocksID,
                               let url = MTGStocksService.shared.webURL(id: id) {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Text("MTGStocks")
                                            .font(.caption.weight(.medium))
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(MD3Theme.primary)
                                }
                            }
                        }

                        // Multi-vendor prices
                        if !detail.vendorPrices.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Compare Prices")
                                    .font(MD3Typography.titleSmall)
                                    .foregroundStyle(MD3Theme.onSurface)
                                ForEach(detail.vendorPrices, id: \.vendor) { vp in
                                    if let url = vp.url {
                                        Link(destination: url) {
                                            vendorRow(vp)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        vendorRow(vp)
                                    }
                                }
                            }
                        }
                    }

                    Text("Price data from MTGStocks.com")
                        .font(.system(size: 9))
                        .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.6))
                }
            }
            .padding(16)
        }
        .task {
            await loadMTGStocksData()
        }
    }

    // MARK: - MTGStocks Loading

    private func loadMTGStocksData() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        let service = MTGStocksService.shared
        guard let id = await service.lookupID(
            cardName: card.name,
            setCode: card.set.code,
            collectorNumber: card.collectorNumber
        ) else { return }
        mtgStocksID = id

        async let historyTask = service.fetchPriceHistory(id: id)
        async let detailTask = service.fetchCard(id: id)
        let (history, detail) = await (historyTask, detailTask)
        priceHistory = history
        mtgStocksCard = detail
    }

    // MARK: - TCG Range

    /// Renders an "estimated low / market / high" tier strip. Scryfall
    /// only exposes the market price, so the low and high are synthesized
    /// from typical TCGPlayer spreads (-15% / +20%) and clearly labeled
    /// as approximations in the footer caption.
    /// Real TCGPlayer Low / Market / High from MTGStocks data.
    @ViewBuilder
    private func tcgRangeReal(low: Double, market: Double, high: Double, preferred: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TCGPlayer range")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .textCase(.uppercase)
                Spacer()
            }
            HStack(alignment: .top, spacing: 0) {
                tier(label: "Low", amount: low, preferred: preferred, color: .green)
                Divider().frame(height: 36)
                tier(label: "Market", amount: market, preferred: preferred, color: MD3Theme.primary, emphasized: true)
                Divider().frame(height: 36)
                tier(label: "High", amount: high, preferred: preferred, color: .red)
            }
            .padding(10)
            .background(MD3Theme.surfaceVariant.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Fallback estimated range when MTGStocks data isn't available.
    @ViewBuilder
    private func tcgRange(marketUSD: Double, preferred: String) -> some View {
        let low = marketUSD * 0.85
        let high = marketUSD * 1.20
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TCGPlayer range (estimated)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .textCase(.uppercase)
                Spacer()
            }
            HStack(alignment: .top, spacing: 0) {
                tier(label: "Low", amount: low, preferred: preferred, color: .green)
                Divider().frame(height: 36)
                tier(label: "Market", amount: marketUSD, preferred: preferred, color: MD3Theme.primary, emphasized: true)
                Divider().frame(height: 36)
                tier(label: "High", amount: high, preferred: preferred, color: .red)
            }
            .padding(10)
            .background(MD3Theme.surfaceVariant.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func tier(label: String, amount: Double, preferred: String, color: Color, emphasized: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(formatLocal(amount, currency: preferred))
                .font(.system(size: emphasized ? 17 : 15, weight: emphasized ? .bold : .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// Converts a USD amount to the user's preferred display currency.
    /// Falls back to the original USD string if the rate isn't available.
    private func formatLocal(_ usd: Double, currency: String) -> String {
        if currency == "USD" {
            return String(format: "$%.2f", usd)
        }
        if let converted = currencyService.convert(usd, to: currency) {
            return LocalCurrency.format(converted, currency: currency)
        }
        // Rate unavailable — surface raw USD so we never show nothing.
        return String(format: "$%.2f", usd)
    }

    private func sourceLabel(preferred: String) -> String {
        let conversionNote = preferred == "USD"
            ? ""
            : " · converted to \(preferred) via frankfurter.app"
        let hasRealPrices = mtgStocksCard?.tcgLow != nil
        if hasRealPrices {
            return "Low/Market/High from TCGPlayer via MTGStocks.\(conversionNote)"
        }
        return "Market price from TCGPlayer via Scryfall. Low/high are estimated (-15% / +20%).\(conversionNote)"
    }

    // MARK: - Subviews

    private func priceRow(source: String, primary: String, secondary: String?) -> some View {
        HStack {
            Text(source)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurface)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(primary)
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.primary)
                    .monospacedDigit()
                if let secondary {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .monospacedDigit()
                }
            }
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

    private func vendorRow(_ vp: MTGStocksCard.VendorPrice) -> some View {
        HStack {
            Text(vp.vendor)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurface)
            if vp.isFoil {
                Text("Foil")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text(String(format: "$%.2f", vp.price))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(MD3Theme.primary)
            if vp.url != nil {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
    }
}
