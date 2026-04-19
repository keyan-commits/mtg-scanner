import SwiftUI

/// Cross-deck shopping list. Flattens every `.needed` PurchaseItem across
/// every deck, groups by card identity (name + set + collector number), and
/// shows total quantity, estimated USD price, and which decks need each card.
///
/// The "New Order from List" button seeds a `MarkOrderReceivedSheet` with
/// pre-formatted paste text so the user can immediately turn the list into
/// an order.
struct ShoppingListScreen: View {

    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol

    @State private var groups: [ShoppingGroup] = []
    @State private var priceCache: [String: Double] = [:]
    @State private var isLoading: Bool = true
    @State private var sortMode: SortMode = .quantity
    @State private var showNewOrderSheet: Bool = false
    /// When true, subtract owned-collection counts from each row's quantity.
    /// Off by default — the user may want the collection cards reserved for
    /// other decks. Manual opt-in.
    @State private var subtractCollection: Bool = false
    /// `[scryfallID: ownedCount]` snapshot loaded once per appear. Used by
    /// the subtraction logic so we don't refetch on every render.
    @State private var ownedByScryfallID: [String: Int] = [:]
    @Bindable private var currencyService = CurrencyService.shared

    enum SortMode: String, CaseIterable, Identifiable {
        case quantity = "Most needed"
        case name = "Name"
        case priceDesc = "Price ↓"
        var id: String { rawValue }
    }

    /// One row in the shopping list — all needed copies of one printing.
    struct ShoppingGroup: Identifiable {
        let id: String // setCode|collectorNumber|cardName
        let cardName: String
        let setName: String
        let setCode: String
        let collectorNumber: String
        let manaCost: String?
        let typeLine: String?
        let items: [PurchaseItem]
        var quantity: Int { items.count }

        struct DeckEntry {
            let deck: DeckList?
            let name: String
            let count: Int
        }

        /// Distinct decks with per-deck count. Each entry includes the
        /// `DeckList` object so the row can navigate to it.
        var deckBreakdown: [DeckEntry] {
            // Group by deck.id (or "-" for orphans)
            let grouped = Dictionary(grouping: items) { $0.deck?.id.uuidString ?? "-" }
            return grouped
                .map { _, items -> DeckEntry in
                    let deck = items.first?.deck
                    return DeckEntry(deck: deck, name: deck?.name ?? "—", count: items.count)
                }
                .sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading shopping list…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        summaryHeader
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(sortedGroups) { group in
                            shoppingRow(group)
                        }
                        if subtractCollection && sortedGroups.isEmpty && !groups.isEmpty {
                            Text("Every needed card is already in your collection.")
                                .font(.caption)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    } header: {
                        HStack {
                            if subtractCollection {
                                Text("\(sortedGroups.count) still need")
                            } else {
                                Text("\(groups.count) cards")
                            }
                            Spacer()
                            Toggle("Subtract collection", isOn: $subtractCollection)
                                .toggleStyle(.button)
                                .font(.caption2)
                                .controlSize(.mini)
                            Picker("Sort", selection: $sortMode) {
                                ForEach(SortMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.caption)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Shopping List")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    ScreenHelpButton(title: "Shopping List", sections: [
                        HelpSection(icon: "list.bullet", title: "What you see",
                                    body: "Every Needed card across every deck, deduped by printing. Quantity is the total copies you still need to buy."),
                        HelpSection(icon: "creditcard", title: "Estimated total",
                                    body: "The summary at the top shows Scryfall USD prices × quantity for everything still needed. Rough budget number — your real seller might charge more or less."),
                        HelpSection(icon: "arrow.up.and.down", title: "Sort modes",
                                    body: "Most needed = sort by quantity desc (4-of's first). Name = alphabetical. Price ↓ = sort by line total desc so the biggest spend items rise to the top."),
                        HelpSection(icon: "rectangle.stack.fill", title: "Subtract collection (manual)",
                                    body: "Off by default. Tap the toggle in the section header to subtract cards you already own from the list. Useful for seeing only what you actually need to buy. Off when you want to keep collection cards reserved for other decks."),
                        HelpSection(icon: "arrow.down.right", title: "Price drift badges",
                                    body: "When the live Scryfall price differs ≥5% from when you added the card to a deck, a green/red badge shows the change. Green = it's cheaper now (buy!). Red = it's more expensive."),
                        HelpSection(icon: "rectangle.stack", title: "Deck attribution chips",
                                    body: "The chips below each card show which decks need it and how many copies each. Tap a chip to jump straight to that deck."),
                        HelpSection(icon: "shippingbox.and.arrow.backward", title: "Order from list",
                                    body: "The toolbar button opens an empty bulk-mark-ordered sheet so you can paste a real seller's confirmation. Don't worry if the shop only has some of what you need — the parser matches whatever you paste."),
                    ])
                    if !groups.isEmpty {
                        Button {
                            showNewOrderSheet = true
                        } label: {
                            Label("Order", systemImage: "shippingbox.and.arrow.backward")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNewOrderSheet) {
            // Open the bulk-order sheet empty — the user pastes their actual
            // seller confirmation. We don't pre-fill because shops never
            // have everything on the wishlist.
            MarkOrderReceivedSheet(
                deck: nil,
                deckRepository: deckRepository,
                onDone: {
                    Task { await reload() }
                }
            )
        }
        .task {
            await reload()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cart")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("Nothing to buy")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Every card across your decks is either ordered or already in hand. Add more cards to a deck to see them here.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Summary Header

    @ViewBuilder
    private var summaryHeader: some View {
        let preferred = LocalCurrency.current
        let totalCards = groups.reduce(0) { $0 + $1.quantity }
        let totalUSD = estimatedTotalUSD()
        let convertedTotal = totalUSD.flatMap { currencyService.convert($0, to: preferred) }
        let deckCount = uniqueDecks().count
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(totalCards)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                Text("cards needed")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Spacer()
                if let convertedTotal {
                    Text("≈ \(LocalCurrency.format(convertedTotal, currency: preferred))")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.primary)
                }
            }
            Text("Across \(deckCount) deck\(deckCount == 1 ? "" : "s") · prices via Scryfall + frankfurter.app")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func shoppingRow(_ group: ShoppingGroup) -> some View {
        let preferred = LocalCurrency.current
        let usd = priceCache[priceKey(setCode: group.setCode, collector: group.collectorNumber)]
        let lineTotalUSD = usd.map { $0 * Double(group.quantity) }
        let convertedLine = lineTotalUSD.flatMap { currencyService.convert($0, to: preferred) }
        let convertedUnit = usd.flatMap { currencyService.convert($0, to: preferred) }
        let drift = priceDrift(for: group, currentUSD: usd)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(group.quantity)×")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .frame(minWidth: 28, alignment: .trailing)
                Text(group.cardName)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                if let manaCost = group.manaCost, !manaCost.isEmpty {
                    ManaCostView(cost: manaCost, size: 13)
                }
                Spacer()
                if let convertedLine {
                    Text(LocalCurrency.format(convertedLine, currency: preferred))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MD3Theme.primary)
                        .monospacedDigit()
                }
            }
            HStack {
                Text("\(group.setName) · #\(group.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Spacer()
                if let convertedUnit {
                    Text("\(LocalCurrency.format(convertedUnit, currency: preferred)) ea")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
            if let drift {
                priceDriftBadge(drift)
            }
            // Subtle "in collection" hint when subtraction is OFF — shows the
            // user where they could save money by reusing physical cards.
            if !subtractCollection,
               let id = group.items.first?.scryfallID,
               let owned = ownedByScryfallID[id], owned > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption2)
                    Text("\(owned) in collection")
                        .font(.caption2)
                }
                .foregroundStyle(.green)
            }
            // Deck attribution chips
            if !group.deckBreakdown.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(group.deckBreakdown, id: \.name) { entry in
                            if let deck = entry.deck {
                                NavigationLink {
                                    DeckDetailView(deck: deck, repository: deckRepository, cardRepository: cardRepository)
                                } label: {
                                    deckChip(name: entry.name, count: entry.count)
                                }
                                .buttonStyle(.plain)
                            } else {
                                deckChip(name: entry.name, count: entry.count)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Price drift

    /// Direction + percentage of the live USD price vs. the price snapshot
    /// taken when the user added the card. Returns nil if either side is
    /// unknown or the change is < 5% (noise threshold).
    private struct PriceDrift {
        let percent: Double  // signed; positive = went up, negative = dropped
        let snapshotUSD: Double
        let currentUSD: Double
    }

    private func priceDrift(for group: ShoppingGroup, currentUSD: Double?) -> PriceDrift? {
        guard let currentUSD,
              let representative = group.items.first,
              let snapshot = representative.priceAtAddUSD,
              snapshot > 0 else { return nil }
        let change = (currentUSD - snapshot) / snapshot * 100
        if abs(change) < 5 { return nil }
        return PriceDrift(percent: change, snapshotUSD: snapshot, currentUSD: currentUSD)
    }

    @ViewBuilder
    private func priceDriftBadge(_ drift: PriceDrift) -> some View {
        let dropped = drift.percent < 0
        HStack(spacing: 4) {
            Image(systemName: dropped ? "arrow.down.right" : "arrow.up.right")
                .font(.caption2.weight(.bold))
            Text(String(format: "%@%.0f%%", dropped ? "" : "+", drift.percent))
                .font(.caption2.weight(.bold))
                .monospacedDigit()
            Text("vs $\(MoneyFormat.compact(drift.snapshotUSD)) at add")
                .font(.caption2)
        }
        .foregroundStyle(dropped ? .green : .red)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((dropped ? Color.green : Color.red).opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func deckChip(name: String, count: Int) -> some View {
        Text("\(name) ×\(count)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(MD3Theme.onSecondaryContainer)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(MD3Theme.secondaryContainer)
            .clipShape(Capsule())
    }

    // MARK: - Sorting

    private var sortedGroups: [ShoppingGroup] {
        // Optionally subtract owned-collection inventory.
        let base: [ShoppingGroup]
        if subtractCollection {
            base = groups.compactMap { group in
                let owned = ownedByScryfallID[group.items.first?.scryfallID ?? ""] ?? 0
                if owned >= group.quantity { return nil }   // fully covered → hide
                if owned == 0 { return group }              // none owned → unchanged
                // Drop the first `owned` items so the remaining count reflects
                // what's still missing after collection.
                var trimmed = group
                trimmed = ShoppingGroup(
                    id: group.id,
                    cardName: group.cardName,
                    setName: group.setName,
                    setCode: group.setCode,
                    collectorNumber: group.collectorNumber,
                    manaCost: group.manaCost,
                    typeLine: group.typeLine,
                    items: Array(group.items.dropFirst(owned))
                )
                return trimmed
            }
        } else {
            base = groups
        }
        switch sortMode {
        case .quantity:
            return base.sorted { $0.quantity > $1.quantity }
        case .name:
            return base.sorted { $0.cardName < $1.cardName }
        case .priceDesc:
            return base.sorted { (a, b) -> Bool in
                let pa = priceCache[priceKey(setCode: a.setCode, collector: a.collectorNumber)] ?? 0
                let pb = priceCache[priceKey(setCode: b.setCode, collector: b.collectorNumber)] ?? 0
                return (pa * Double(a.quantity)) > (pb * Double(b.quantity))
            }
        }
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        // Snapshot collection for optional subtraction.
        ownedByScryfallID = (try? deckRepository.ownedQuantitiesByScryfallID()) ?? [:]

        let needed = (try? deckRepository.fetchItemsByStatus(.needed)) ?? []

        // Group by printing identity
        let byKey = Dictionary(grouping: needed) { item in
            "\(item.setCode)|\(item.collectorNumber)|\(item.cardName)"
        }
        let built: [ShoppingGroup] = byKey
            .map { key, items in
                let representative = items[0]
                return ShoppingGroup(
                    id: key,
                    cardName: representative.cardName,
                    setName: representative.setName,
                    setCode: representative.setCode,
                    collectorNumber: representative.collectorNumber,
                    manaCost: representative.manaCost,
                    typeLine: representative.typeLine,
                    items: items
                )
            }
            .sorted { $0.cardName < $1.cardName }
        groups = built

        // Fetch prices in parallel batches
        await withTaskGroup(of: (String, Double?).self) { taskGroup in
            for group in built {
                let key = priceKey(setCode: group.setCode, collector: group.collectorNumber)
                guard priceCache[key] == nil else { continue }
                taskGroup.addTask {
                    if let card = try? await cardRepository.fetchCard(set: group.setCode, collectorNumber: group.collectorNumber),
                       let usdString = card.prices.usd, let usd = Double(usdString) {
                        return (key, usd)
                    }
                    return (key, nil)
                }
            }
            for await (key, price) in taskGroup {
                if let price { priceCache[key] = price }
            }
        }
    }

    private func priceKey(setCode: String, collector: String) -> String {
        "\(setCode)|\(collector)"
    }

    private func estimatedTotalUSD() -> Double? {
        var total: Double = 0
        var hasAny = false
        for group in groups {
            if let usd = priceCache[priceKey(setCode: group.setCode, collector: group.collectorNumber)] {
                total += usd * Double(group.quantity)
                hasAny = true
            }
        }
        return hasAny ? total : nil
    }

    private func uniqueDecks() -> Set<String> {
        var decks: Set<String> = []
        for group in groups {
            for entry in group.deckBreakdown {
                decks.insert(entry.name)
            }
        }
        return decks
    }

    private func formatPrice(_ price: Double) -> String { MoneyFormat.compactLarge(price) }
}
