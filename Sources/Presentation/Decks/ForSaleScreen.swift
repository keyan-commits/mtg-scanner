import SwiftUI

/// Personal sales pipeline: every card the user has tagged for sale,
/// plus a sub-tab of the historical sales ledger. Modelled on
/// RecentlyAddedScreen so the row layout / summary tile pattern feels
/// consistent across the Decks tab.
///
/// Foil and nonfoil are tracked as separate sub-quantities on each
/// CollectionItem so a single row can render two listings (e.g. "1
/// nonfoil at ₱330 + 2 foil at ₱1,750"). The ledger sub-tab preserves
/// items even after `quantity == 0` — that's the differentiator vs
/// Deckbox / ManaBox which delete sold cards and lose the history.
struct ForSaleScreen: View {

    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol

    enum Tab: Hashable { case listed, sold }

    @State private var tab: Tab = .listed
    @State private var listedItems: [CollectionItem] = []
    @State private var soldItems: [CollectionItem] = []
    @State private var resolvedCards: [String: Card] = [:]
    @State private var editingItem: CollectionItem?
    @State private var sellingItem: CollectionItem?
    @Bindable private var currencyService = CurrencyService.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Listed").tag(Tab.listed)
                Text("Sold").tag(Tab.sold)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch tab {
            case .listed:
                if listedItems.isEmpty { emptyListedState } else { listedBody }
            case .sold:
                if soldItems.isEmpty { emptySoldState } else { soldBody }
            }
        }
        .navigationTitle("For Sale")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .task { await currencyService.refreshIfStale() }
        .sheet(item: $editingItem) { item in
            ListForSaleSheet(
                item: item,
                deckRepository: deckRepository,
                onClose: { reload() }
            )
        }
        .sheet(item: $sellingItem) { item in
            RecordSaleSheet(
                item: item,
                deckRepository: deckRepository,
                onClose: { reload() }
            )
        }
    }

    // MARK: - Listed tab

    private var listedBody: some View {
        List {
            SwiftUI.Section {
                listedSummary
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            SwiftUI.Section("\(listedItems.count) listings") {
                ForEach(listedItems) { item in
                    Button {
                        editingItem = item
                    } label: {
                        listedRow(item)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Sold") { sellingItem = item }
                            .tint(.green)
                        Button("Withdraw") {
                            try? deckRepository.unmarkForSale(item)
                            reload()
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var listedSummary: some View {
        let preferred = LocalCurrency.current
        let totalAskingUSD = listedItems.reduce(0.0) { acc, item in
            let nonfoil = (item.askingPriceUSD ?? item.currentValueUSD ?? 0) * Double(item.forSaleNonfoilQuantity)
            let foil = (item.askingPriceFoilUSD ?? item.currentValueFoilUSD ?? 0) * Double(item.forSaleFoilQuantity)
            return acc + nonfoil + foil
        }
        let totalCopies = listedItems.reduce(0) { $0 + $1.forSaleQuantity }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total asking")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.75))
                    .textCase(.uppercase)
                if let converted = currencyService.convert(totalAskingUSD, to: preferred) {
                    Text(LocalCurrency.format(converted, currency: preferred))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MD3Theme.onPrimaryContainer)
                } else {
                    Text(LocalCurrency.format(totalAskingUSD, currency: "USD"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MD3Theme.onPrimaryContainer)
                }
            }
            HStack(spacing: 12) {
                statTile(value: "\(totalCopies)", label: "Copies")
                Divider().frame(height: 28)
                statTile(value: "\(listedItems.count)", label: "Entries")
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [MD3Theme.primaryContainer, MD3Theme.primaryContainer.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func listedRow(_ item: CollectionItem) -> some View {
        let preferred = LocalCurrency.current
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.cardName)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                Text("\(item.setName) · #\(item.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
                listingFinishLine(item, preferred: preferred)
                if let listedAt = item.listedAt {
                    Text("Listed \(relativeDate(listedAt))" +
                         (item.listedOn.map { " · \($0)" } ?? ""))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.8))
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
        }
        .padding(.vertical, 2)
    }

    /// "Foil 2× ₱1,750ea · Nonfoil 1× ₱330ea" — collapses to a single
    /// chip when only one finish is listed.
    @ViewBuilder
    private func listingFinishLine(_ item: CollectionItem, preferred: String) -> some View {
        HStack(spacing: 6) {
            if item.forSaleFoilQuantity > 0 {
                pricingChip(
                    label: "Foil",
                    qty: item.forSaleFoilQuantity,
                    askUSD: item.askingPriceFoilUSD ?? item.currentValueFoilUSD,
                    color: .purple,
                    preferred: preferred
                )
            }
            if item.forSaleNonfoilQuantity > 0 {
                pricingChip(
                    label: "NM",
                    qty: item.forSaleNonfoilQuantity,
                    askUSD: item.askingPriceUSD ?? item.currentValueUSD,
                    color: MD3Theme.primary,
                    preferred: preferred
                )
            }
        }
    }

    private func pricingChip(label: String, qty: Int, askUSD: Double?,
                             color: Color, preferred: String) -> some View {
        let priceText: String? = {
            guard let usd = askUSD else { return nil }
            if preferred == "USD" { return String(format: "$%.2f", usd) }
            return currencyService.convert(usd, to: preferred)
                .map { LocalCurrency.format($0, currency: preferred) }
        }()
        return HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(color)
                .clipShape(Capsule())
            Text("×\(qty)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(MD3Theme.onSurface)
            if let priceText {
                Text(priceText + "ea")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        }
    }

    // MARK: - Sold tab

    private var soldBody: some View {
        List {
            SwiftUI.Section {
                soldSummary
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            SwiftUI.Section("\(soldItems.count) sold") {
                ForEach(soldItems) { item in
                    soldRow(item)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var soldSummary: some View {
        let preferred = LocalCurrency.current
        let realizedUSD = soldItems.reduce(0.0) { acc, item in
            // We don't have per-sale price for every historical sale —
            // approximate using lastSoldPriceUSD × soldQuantity as a
            // working estimate. Refines as we capture per-sale prices.
            let unit = item.lastSoldPriceUSD ?? 0
            return acc + unit * Double(item.soldQuantity)
        }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Realized (est.)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.75))
                    .textCase(.uppercase)
                if let converted = currencyService.convert(realizedUSD, to: preferred) {
                    Text(LocalCurrency.format(converted, currency: preferred))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MD3Theme.onPrimaryContainer)
                }
            }
            HStack(spacing: 12) {
                let totalSold = soldItems.reduce(0) { $0 + $1.soldQuantity }
                statTile(value: "\(totalSold)", label: "Copies sold")
                Divider().frame(height: 28)
                statTile(value: "\(soldItems.count)", label: "Entries")
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [MD3Theme.primaryContainer, MD3Theme.primaryContainer.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func soldRow(_ item: CollectionItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.cardName)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                Text("\(item.setName) · #\(item.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
                if let when = item.lastSoldAt {
                    Text("Sold \(relativeDate(when)) · ×\(item.soldQuantity)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.8))
                }
            }
            Spacer(minLength: 8)
            if let unit = item.lastSoldPriceUSD {
                let preferred = LocalCurrency.current
                let line = unit * Double(item.soldQuantity)
                let display = currencyService.convert(line, to: preferred)
                    .map { LocalCurrency.format($0, currency: preferred) }
                    ?? String(format: "$%.2f", line)
                Text(display)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(MD3Theme.onPrimaryContainer)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.7))
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var emptyListedState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tag")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("Nothing listed")
                .font(MD3Typography.titleLarge)
            Text("Tag cards from Collection or any card detail to add them here. Foil and nonfoil are tracked separately so you can list them at different prices.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var emptySoldState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray.full")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("No sales yet")
                .font(MD3Typography.titleLarge)
            Text("Once you mark a listing as Sold, it shows up here as a permanent ledger entry — even after the card leaves your collection.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Data

    private func reload() {
        listedItems = (try? deckRepository.fetchForSale()) ?? []
        soldItems = (try? deckRepository.fetchSoldHistory()) ?? []
    }
}
