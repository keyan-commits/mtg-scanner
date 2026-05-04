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
    @State private var hareruyaPrice: HareruyaPrice?

    var body: some View {
        let preferred = LocalCurrency.current
        let marketUSD = card.prices.usd.flatMap(Double.init)
        let foilUSD = card.prices.usdFoil.flatMap(Double.init)
        let eurAmount = card.prices.eur.flatMap(Double.init)
        MD3Card {
            VStack(alignment: .leading, spacing: 14) {
                // Foil-only printings (FNM, Secret Lair foil drops, Magic
                // Online promos) have no nonfoil price — the NM/range panel
                // would only ever show garbage or a non-foil reprint's
                // numbers. Skip it and let the foil row stand alone below.
                if !card.isFoilOnly {
                    Text("Market Prices (NM)")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    // TCGPlayer's three published tiers: Low / Mid /
                    // Market. Layout matches ManaBox + TCGPlayer's own
                    // product page — labeled rows, NOT a sorted bar.
                    // Mid (median listings) and Market (algorithmic
                    // reference) aren't always sorted, so a left-to-
                    // right "range" metaphor reads as a bug. The old
                    // synthetic "High" tier (capped 3× market) was just
                    // outlier listings; dropped entirely.
                    if let detail = mtgStocksCard,
                       detail.tcgLow != nil || detail.tcgMid != nil || detail.tcgMarket != nil {
                        tcgTierRows(detail: detail, preferred: preferred)
                    } else if let rangeUSD = marketUSD ?? foilUSD {
                        // No MTGStocks data — fall back to Scryfall's
                        // single market price as a labeled row.
                        priceRow(
                            source: "TCGPlayer Market (est.)",
                            primary: formatLocal(rangeUSD, currency: preferred),
                            secondary: preferred == "USD" ? nil : String(format: "$%.2f USD", rangeUSD)
                        )
                    }

                    if marketUSD != nil || foilUSD != nil || eurAmount != nil {
                        Divider()
                    }
                }

                // The standalone "TCGPlayer Market" row used to live here
                // sourced from `card.prices.usd` (Scryfall daily bulk).
                // Removed because the TCGPlayer Range bar above already
                // shows Market alongside Low/High from a single source —
                // showing the same nominal "TCGPlayer Market" twice with
                // different freshness was confusing. Foil and EUR rows
                // below stay because they're distinct numbers, not
                // duplicates of the Range bar.

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

                // Hareruya inline price (fetched from API)
                if let hp = hareruyaPrice {
                    HStack {
                        Text("Hareruya")
                            .font(MD3Typography.bodyMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                        Spacer()
                        Text(hp.formattedPrice)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MD3Theme.primary)
                    }
                }

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
                    if let history = priceHistory, !history.averagePrices(preferFoil: card.isFoilOnly).isEmpty {
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
                                dataPoints: history.averagePrices(preferFoil: card.isFoilOnly),
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
        .task(id: card.scryfallID) {
            // Reset when card changes (e.g. Other Printings navigation)
            priceHistory = nil
            mtgStocksCard = nil
            mtgStocksID = nil
            hareruyaPrice = nil
            isLoadingHistory = false
            await loadMTGStocksData()
        }
        .task(id: "hareruya-\(card.scryfallID)") {
            await loadHareruyaPrice()
        }
    }

    private func loadHareruyaPrice() async {
        let service = HareruyaPriceService()
        hareruyaPrice = try? await service.fetchNMPrice(cardName: card.name)
    }

    // MARK: - MTGStocks Loading

    private func loadMTGStocksData() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        let service = MTGStocksService.shared
        guard let id = await service.lookupID(
            cardName: card.name,
            setCode: card.set.code,
            collectorNumber: card.collectorNumber,
            promoTypes: card.promoTypes
        ) else { return }
        mtgStocksID = id

        async let historyTask = service.fetchPriceHistory(id: id)
        async let detailTask = service.fetchCard(id: id, isFoilOnly: card.isFoilOnly)
        let (history, detail) = await (historyTask, detailTask)
        priceHistory = history
        mtgStocksCard = detail
    }

    // MARK: - TCG Tier Rows

    /// Renders TCGPlayer's three published tiers (Low / Mid / Market)
    /// as a labeled vertical list. Layout matches ManaBox + TCGPlayer's
    /// product page so users coming from those see the same numbers
    /// under the same names.
    @ViewBuilder
    private func tcgTierRows(detail: MTGStocksCard, preferred: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TCGPlayer (NM)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .textCase(.uppercase)
            if let low = detail.tcgLow {
                tcgTierRow(label: "Low", amount: low, color: .green, preferred: preferred)
            }
            if let mid = detail.tcgMid {
                tcgTierRow(label: "Mid", amount: mid, color: MD3Theme.onSurface, preferred: preferred)
            }
            if let market = detail.tcgMarket {
                tcgTierRow(label: "Market", amount: market, color: MD3Theme.primary, preferred: preferred, emphasized: true)
            }
        }
        .padding(10)
        .background(MD3Theme.surfaceVariant.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tcgTierRow(label: String, amount: Double, color: Color, preferred: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 60, alignment: .leading)
            Spacer()
            Text(formatLocal(amount, currency: preferred))
                .font(.system(size: emphasized ? 16 : 14, weight: emphasized ? .bold : .semibold, design: .monospaced))
                .foregroundStyle(MD3Theme.onSurface)
                .monospacedDigit()
            if preferred != "USD" {
                Text(String(format: "$%.2f", amount))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .frame(minWidth: 60, alignment: .trailing)
            }
        }
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
            || mtgStocksCard?.tcgMid != nil
            || mtgStocksCard?.tcgMarket != nil
        if hasRealPrices {
            return "Low/Mid/Market from TCGPlayer via MTGStocks.\(conversionNote)"
        }
        return "Market price from TCGPlayer via Scryfall.\(conversionNote)"
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
