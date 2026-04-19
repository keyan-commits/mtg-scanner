import SwiftUI

/// Top-level screen showing every card the user physically owns. Cards are
/// added either manually via the search sheet, or automatically when an
/// order is marked as Arrived.
struct CollectionScreen: View {

    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol

    @State private var items: [CollectionItem] = []
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var showAddSheet: Bool = false
    @State private var editingItem: CollectionItem?
    @State private var showBulkStoreSheet: Bool = false
    @State private var bulkStoreName: String = ""
    @State private var sortMode: SortMode = .name
    @State private var groupMode: GroupMode = .none
    @State private var viewMode: ViewMode = .list
    @State private var setFilter: String? = nil
    @State private var typeFilter: CardCategory? = nil
    @State private var colorFilter: ColorFilter = .any
    @State private var foilsOnly: Bool = false
    @State private var priceCache: [String: Double] = [:]
    @State private var pricesLoaded: Bool = false
    @State private var resolvedCards: [String: Card] = [:]
    /// Maps archetype display name → set of card names belonging to
    /// that archetype. Pre-loaded from the CommonCardsAggregator cache
    /// on appear so groupByArchetype is instant.
    @State private var archetypeCardMap: [String: Set<String>] = [:]
    @Bindable private var currencyService = CurrencyService.shared
    private let aggregator: CommonCardsAggregatorProtocol = CommonCardsAggregator()

    private enum ViewMode: String, CaseIterable, Hashable {
        case list, grid
        var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    enum GroupMode: String, CaseIterable, Identifiable {
        case none = "No Grouping"
        case color = "Color"
        case expansion = "Expansion"
        case type = "Type"
        case tribe = "Tribe"
        case archetype = "Deck Archetype"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .none: return "line.3.horizontal"
            case .color: return "paintpalette"
            case .expansion: return "rectangle.stack"
            case .type: return "tag"
            case .tribe: return "person.3"
            case .archetype: return "trophy"
            }
        }
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case name = "Name"
        case quantity = "Quantity"
        case setName = "Set"
        case recent = "Recently added"
        case valueDesc = "Value ↓"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .name: return "textformat"
            case .quantity: return "number"
            case .setName: return "rectangle.stack"
            case .recent: return "clock"
            case .valueDesc: return "dollarsign.circle"
            }
        }
    }

    enum ColorFilter: String, CaseIterable, Identifiable {
        case any = "Any"
        case white = "White"
        case blue = "Blue"
        case black = "Black"
        case red = "Red"
        case green = "Green"
        case colorless = "Colorless"
        var id: String { rawValue }
        var symbol: String? {
            switch self {
            case .any: return nil
            case .white: return "W"
            case .blue: return "U"
            case .black: return "B"
            case .red: return "R"
            case .green: return "G"
            case .colorless: return nil
            }
        }
    }

    /// Distinct set names present in the collection, for the filter menu.
    private var allSets: [String] {
        Array(Set(items.map(\.setName))).sorted()
    }

    /// Filtered + sorted view of `items`.
    private var filtered: [CollectionItem] {
        var result = items

        // Text search
        let q = debouncedSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.cardName.lowercased().contains(q)
                    || $0.setName.lowercased().contains(q)
                    || $0.setCode.lowercased().contains(q)
            }
        }

        // Set filter
        if let setFilter {
            result = result.filter { $0.setName == setFilter }
        }

        // Type filter
        if let typeFilter {
            result = result.filter {
                CardCategory.from(typeLine: $0.typeLine) == typeFilter
            }
        }

        // Color filter (parses manaCost — colorless matches items with no
        // colored mana symbols, "any" returns everything).
        switch colorFilter {
        case .any:
            break
        case .colorless:
            result = result.filter { item in
                guard let cost = item.manaCost else { return true }
                let lower = cost.lowercased()
                return !lower.contains("w") && !lower.contains("u")
                    && !lower.contains("b") && !lower.contains("r")
                    && !lower.contains("g")
            }
        default:
            if let symbol = colorFilter.symbol?.lowercased() {
                result = result.filter {
                    $0.manaCost?.lowercased().contains(symbol) ?? false
                }
            }
        }

        // Foils only
        if foilsOnly {
            result = result.filter { $0.foilQuantity > 0 }
        }

        // Sort
        switch sortMode {
        case .name:
            result.sort { $0.cardName < $1.cardName }
        case .quantity:
            result.sort { $0.quantity > $1.quantity }
        case .setName:
            result.sort {
                if $0.setName == $1.setName { return $0.cardName < $1.cardName }
                return $0.setName < $1.setName
            }
        case .recent:
            result.sort { $0.addedAt > $1.addedAt }
        case .valueDesc:
            result.sort { (a, b) -> Bool in
                let pa = priceCache[a.scryfallID] ?? 0
                let pb = priceCache[b.scryfallID] ?? 0
                return (pa * Double(a.quantity)) > (pb * Double(b.quantity))
            }
        }

        return result
    }

    private var hasActiveFilter: Bool {
        setFilter != nil || typeFilter != nil || colorFilter != .any || foilsOnly
    }

    private var totalUniqueCards: Int { items.count }
    private var totalCopies: Int { items.reduce(0) { $0 + $1.quantity } }

    // MARK: - Grouping

    private struct GroupedSection: Identifiable {
        let title: String
        let items: [CollectionItem]
        var id: String { title }
    }

    private var groupedFiltered: [GroupedSection] {
        let flat = filtered
        switch groupMode {
        case .none:
            return [GroupedSection(title: "\(flat.count) cards", items: flat)]
        case .color:
            return groupByColor(flat)
        case .expansion:
            return groupBySet(flat)
        case .type:
            return groupByType(flat)
        case .tribe:
            return groupByTribe(flat)
        case .archetype:
            return groupByArchetype(flat)
        }
    }

    private func groupByColor(_ items: [CollectionItem]) -> [GroupedSection] {
        let colorOrder = ["White", "Blue", "Black", "Red", "Green", "Multicolor", "Colorless"]
        let grouped = Dictionary(grouping: items) { item -> String in
            guard let cost = item.manaCost?.lowercased() else { return "Colorless" }
            var colors: [String] = []
            if cost.contains("w") { colors.append("White") }
            if cost.contains("u") { colors.append("Blue") }
            if cost.contains("b") { colors.append("Black") }
            if cost.contains("r") { colors.append("Red") }
            if cost.contains("g") { colors.append("Green") }
            if colors.count > 1 { return "Multicolor" }
            return colors.first ?? "Colorless"
        }
        return colorOrder.compactMap { color in
            guard let entries = grouped[color], !entries.isEmpty else { return nil }
            return GroupedSection(title: "\(color) (\(entries.count))", items: entries)
        }
    }

    private func groupBySet(_ items: [CollectionItem]) -> [GroupedSection] {
        let grouped = Dictionary(grouping: items, by: \.setName)
        return grouped.keys.sorted().map { name in
            GroupedSection(title: "\(name) (\(grouped[name]!.count))", items: grouped[name]!)
        }
    }

    private func groupByType(_ items: [CollectionItem]) -> [GroupedSection] {
        let grouped = Dictionary(grouping: items) { CardCategory.from(typeLine: $0.typeLine) }
        return grouped.keys.sorted(by: { $0.sortOrder < $1.sortOrder }).map { cat in
            GroupedSection(title: "\(cat.rawValue) (\(grouped[cat]!.count))", items: grouped[cat]!)
        }
    }

    private func groupByTribe(_ items: [CollectionItem]) -> [GroupedSection] {
        var groups: [String: [CollectionItem]] = [:]
        for item in items {
            let typeLine = item.typeLine ?? ""
            if let dashRange = typeLine.range(of: "—") {
                let subtypes = typeLine[dashRange.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: " ")
                if let firstType = subtypes.first {
                    let tribe = String(firstType)
                    groups[tribe, default: []].append(item)
                } else {
                    groups["Other", default: []].append(item)
                }
            } else {
                groups["Other", default: []].append(item)
            }
        }
        // Largest tribes first, "Other" always last
        return groups.sorted { lhs, rhs in
            if lhs.key == "Other" { return false }
            if rhs.key == "Other" { return true }
            return lhs.value.count > rhs.value.count
        }.map { GroupedSection(title: "\($0.key) (\($0.value.count))", items: $0.value) }
    }

    private func groupByArchetype(_ items: [CollectionItem]) -> [GroupedSection] {
        if archetypeCardMap.isEmpty {
            return [GroupedSection(
                title: "Browse some archetypes first to enable this grouping",
                items: items
            )]
        }
        // For each collection card, find which archetype it best
        // belongs to (first match wins — archetypes are iterated in
        // no guaranteed order, so a card in multiple archetypes may
        // land in any of them; that's acceptable for a grouping view).
        var cardToArchetype: [String: String] = [:]
        for (archetypeName, cardNames) in archetypeCardMap {
            for name in cardNames {
                if cardToArchetype[name] == nil {
                    cardToArchetype[name] = archetypeName
                }
            }
        }
        let grouped = Dictionary(grouping: items) { item in
            cardToArchetype[item.cardName] ?? "Other"
        }
        // Sort: named archetypes first (alphabetical), "Other" last
        let keys = grouped.keys.sorted { lhs, rhs in
            if lhs == "Other" { return false }
            if rhs == "Other" { return true }
            return lhs < rhs
        }
        return keys.map { name in
            GroupedSection(title: "\(name) (\(grouped[name]!.count))", items: grouped[name]!)
        }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                switch viewMode {
                case .list:
                    listBody
                case .grid:
                    gridBody
                }
            }
        }
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search by card name or set")
        .onChange(of: searchText) { _, newValue in
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if searchText == newValue { debouncedSearchText = newValue }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // View mode toggle
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)

                // Group mode menu + bulk actions
                Menu {
                    Picker("Group by", selection: $groupMode) {
                        ForEach(GroupMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    }
                    Divider()
                    Button {
                        showBulkStoreSheet = true
                    } label: {
                        Label("Set Store (All Visible)", systemImage: "storefront")
                    }
                    .disabled(filtered.isEmpty)
                } label: {
                    Image(systemName: groupMode == .none
                          ? "rectangle.3.group"
                          : "rectangle.3.group.fill")
                }

                ScreenHelpButton(title: "Collection", sections: [
                        HelpSection(icon: "rectangle.stack", title: "What lives here",
                                    body: "Every physical card you own. Tracked per printing — 4 Lightning Bolts from M11 and 4 from M10 are two separate rows."),
                        HelpSection(icon: "checkmark.seal.fill", title: "Auto-populated",
                                    body: "When you mark an order as Arrived, every card in it is added to your collection automatically. So just by tracking your orders, your collection stays in sync."),
                        HelpSection(icon: "plus", title: "Add manually",
                                    body: "Tap + to search for a card and add a specific printing. Useful for cards you owned before you started tracking, or for trades."),
                        HelpSection(icon: "line.3.horizontal.decrease.circle", title: "Sort & filter",
                                    body: "The filter button has Sort (Name, Quantity, Set, Recent, Value) and Filter sub-menus (Set, Type, Color, Foils only). The icon fills in when any filter is active."),
                        HelpSection(icon: "hand.tap", title: "Edit a row",
                                    body: "Tap any row to change the quantity or delete the entry. Setting quantity to 0 removes it."),
                        HelpSection(icon: "trash", title: "Delete",
                                    body: "Swipe left on a row to delete it directly."),
                    ])
                    Menu {
                        Picker("Sort", selection: $sortMode) {
                            ForEach(SortMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                        Divider()
                        Menu("Set") {
                            Button("All sets") { setFilter = nil }
                            ForEach(allSets, id: \.self) { set in
                                Button(set) { setFilter = set }
                            }
                        }
                        Menu("Type") {
                            Button("All types") { typeFilter = nil }
                            ForEach(CardCategory.allCases, id: \.self) { category in
                                Button(category.rawValue) { typeFilter = category }
                            }
                        }
                        Menu("Color") {
                            ForEach(ColorFilter.allCases) { color in
                                Button(color.rawValue) { colorFilter = color }
                            }
                        }
                        Toggle("Foils only", isOn: $foilsOnly)
                        if hasActiveFilter {
                            Divider()
                            Button("Clear filters", role: .destructive) {
                                setFilter = nil
                                typeFilter = nil
                                colorFilter = .any
                                foilsOnly = false
                            }
                        }
                    } label: {
                        Image(systemName: hasActiveFilter
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddToCollectionSheet(
                deckRepository: deckRepository,
                cardRepository: cardRepository,
                onAdded: { reload() }
            )
        }
        .sheet(item: $editingItem) { item in
            EditCollectionItemSheet(
                item: item,
                deckRepository: deckRepository,
                onChanged: {
                    editingItem = nil
                    reload()
                }
            )
        }
        .alert("Set Store for All Visible Cards", isPresented: $showBulkStoreSheet) {
            TextField("Store / Seller name", text: $bulkStoreName)
            Button("Apply to \(filtered.count) cards") {
                let source = bulkStoreName.isEmpty ? nil : bulkStoreName
                for item in filtered {
                    item.purchaseSource = source
                }
                bulkStoreName = ""
                reload()
            }
            Button("Cancel", role: .cancel) { bulkStoreName = "" }
        } message: {
            Text("This will set the purchase source for all \(filtered.count) currently visible cards.")
        }
        .onAppear { reload() }
        .task {
            // Refresh exchange rates if stale (24h cache).
            await currencyService.refreshIfStale()
            // Fetch Scryfall prices for any items missing from the cache.
            // Required for the value header + per-row prices.
            await loadPricesIfNeeded()
            // Pre-load the archetype → card-names mapping so the
            // "Group by Deck Archetype" option is instant. Reads from
            // the aggregation cache (populated by Browse Archetypes).
            await loadArchetypeMapping()
        }
    }

    /// Builds the `archetypeCardMap` from every cached aggregation.
    /// Each archetype's universal + per-format cards are collected
    /// into a name set. The display name comes from the curated
    /// `MajorArchetypes` catalog (e.g., "Burn") or falls back to
    /// a capitalized version of the cache key.
    private func loadArchetypeMapping() async {
        let aggregations = await aggregator.allCachedAggregations()
        guard !aggregations.isEmpty else { return }
        var map: [String: Set<String>] = [:]
        for agg in aggregations {
            let allCards = Set(
                agg.universalCards.map(\.cardName)
                + agg.perFormatCards.flatMap { $0.cards.map(\.cardName) }
            )
            let displayName = MajorArchetypes.all
                .first { $0.id == agg.majorArchetypeID }?.name
                ?? agg.majorArchetypeID.split(separator: " ")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
            map[displayName] = allCards
        }
        archetypeCardMap = map
    }

    /// Pulls Scryfall USD prices for items missing from the price cache.
    /// Runs once per appear; cached results persist for the screen
    /// lifetime so scrolling never refetches.
    private func loadPricesIfNeeded() async {
        for item in items where priceCache[item.scryfallID] == nil {
            if let card = try? await cardRepository.fetchCard(
                set: item.setCode,
                collectorNumber: item.collectorNumber
            ),
               let usdString = card.prices.usd,
               let usd = Double(usdString) {
                priceCache[item.scryfallID] = usd
            }
        }
        pricesLoaded = true
    }

    // MARK: - List body

    private var listBody: some View {
        List {
            Section {
                summaryHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            ForEach(groupedFiltered) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        NavigationLink {
                            cardDetailDestination(for: item, in: section.items)
                        } label: {
                            row(item)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                try? deckRepository.deleteCollectionItem(item)
                                reload()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingItem = item
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Grid body

    private var gridBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                summaryHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ForEach(groupedFiltered) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(section.items) { item in
                                    gridCard(item, in: section.items)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(MD3Theme.background)
    }

    private func gridCard(_ item: CollectionItem, in items: [CollectionItem] = []) -> some View {
        NavigationLink {
            cardDetailDestination(for: item, in: items)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if let card = resolvedCards[item.scryfallID],
                       let urlString = card.imageURIs["normal"]
                           ?? card.imageURIs["small"]
                           ?? card.imageURIs["large"],
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                gridPlaceholder(item.cardName)
                            }
                        }
                    } else {
                        gridPlaceholder(item.cardName)
                            .task { await resolveCard(item) }
                    }
                    if item.quantity > 1 {
                        Text("\(item.quantity)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }
                .frame(width: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MD3Theme.outlineVariant, lineWidth: 1)
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func gridPlaceholder(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(MD3Theme.surfaceVariant)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .frame(width: 110)
            .overlay(
                Text(name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    // MARK: - Card detail navigation

    /// Resolves a `CollectionItem` to a `Card` for CardDetailView.
    /// Uses the local DB via set+collectorNumber for an exact printing
    /// match (not fuzzy — the collection item already has printing info).
    @ViewBuilder
    private func cardDetailDestination(for item: CollectionItem, in items: [CollectionItem] = []) -> some View {
        if let card = resolvedCards[item.scryfallID] {
            let sectionCards = items.compactMap { resolvedCards[$0.scryfallID] }
            if sectionCards.count > 1,
               let idx = sectionCards.firstIndex(where: { $0.scryfallID == card.scryfallID }) {
                CardListPagerView(
                    cards: sectionCards,
                    initialIndex: idx,
                    cardRepository: cardRepository,
                    deckRepository: deckRepository
                )
            } else {
                CardDetailView(
                    card: card,
                    repository: cardRepository,
                    deckRepository: deckRepository,
                    onScanAnother: {}
                )
            }
        } else {
            ProgressView("Loading card…")
                .task { await resolveCard(item) }
        }
    }

    private func resolveCard(_ item: CollectionItem) async {
        guard resolvedCards[item.scryfallID] == nil else { return }
        if let card = try? await cardRepository.fetchCard(
            set: item.setCode,
            collectorNumber: item.collectorNumber
        ) {
            resolvedCards[item.scryfallID] = card
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "rectangle.stack")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("Empty collection")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Tap + to add cards manually, or mark an order as arrived to populate this list automatically.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            MD3FilledButton("Add a Card") { showAddSheet = true }
                .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Summary Header

    @ViewBuilder
    private var summaryHeader: some View {
        let totalUSD = totalCollectionValueUSD()
        let preferred = LocalCurrency.current
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated value")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.75))
                        .textCase(.uppercase)
                    if let totalUSD,
                       let converted = currencyService.convert(totalUSD, to: preferred) {
                        Text(LocalCurrency.format(converted, currency: preferred))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(MD3Theme.onPrimaryContainer)
                    } else if pricesLoaded {
                        Text("—")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.5))
                    } else {
                        ProgressView()
                            .scaleEffect(0.75)
                            .frame(height: 32)
                    }
                }
                Spacer()
            }
            HStack(spacing: 12) {
                statTile(value: "\(totalCopies)", label: "Copies")
                Divider().frame(height: 28)
                statTile(value: "\(totalUniqueCards)", label: "Uniques")
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

    private static let cachedValueKey = "collectionCachedValueUSD"
    private static let cachedValueTimestamp = "collectionCachedValueAt"

    private func totalCollectionValueUSD() -> Double? {
        // Use cached value if computed within the last hour
        let cachedAt = UserDefaults.standard.double(forKey: Self.cachedValueTimestamp)
        if cachedAt > 0 && Date().timeIntervalSince1970 - cachedAt < 3600 {
            let cached = UserDefaults.standard.double(forKey: Self.cachedValueKey)
            if cached > 0 { return cached }
        }

        var total: Double = 0
        var hasAny = false
        for item in items {
            if let usd = priceCache[item.scryfallID] {
                total += usd * Double(item.quantity)
                hasAny = true
            }
        }
        if hasAny {
            UserDefaults.standard.set(total, forKey: Self.cachedValueKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.cachedValueTimestamp)
        }
        return hasAny ? total : nil
    }

    // MARK: - Row

    private func row(_ item: CollectionItem) -> some View {
        let preferred = LocalCurrency.current
        let currentUSD = priceCache[item.scryfallID]
        let lineUSD = currentUSD.map { $0 * Double(item.quantity) }
        let convertedLine = lineUSD.flatMap { currencyService.convert($0, to: preferred) }
        let convertedUnit = currentUSD.flatMap { currencyService.convert($0, to: preferred) }
        let change = priceChange(item: item, currentUSD: currentUSD)
        return VStack(spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.cardName)
                            .font(MD3Typography.bodyMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                            .lineLimit(1)
                        if let manaCost = item.manaCost, !manaCost.isEmpty {
                            ManaCostView(cost: manaCost, size: 13)
                        }
                        if item.foilQuantity > 0 {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("\(item.setName) · #\(item.collectorNumber)")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                            .lineLimit(1)
                        if let source = item.purchaseSource {
                            Text(source)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(MD3Theme.tertiary)
                                .clipShape(Capsule())
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if let convertedLine {
                        Text(LocalCurrency.format(convertedLine, currency: preferred))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(MD3Theme.onSurface)
                            .monospacedDigit()
                    }
                    if let convertedUnit, item.quantity > 1 {
                        Text("\(LocalCurrency.format(convertedUnit, currency: preferred)) ea")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                            .monospacedDigit()
                    }
                    if let change {
                        Text(change.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(change.isUp ? .red : .green)
                            .monospacedDigit()
                    }
                }
            }

            // Inline quantity controls — +/- buttons so the user
            // can adjust how many copies they own without opening
            // the edit sheet. Deletes the item if quantity hits 0.
            HStack(spacing: 0) {
                Button {
                    adjustQuantity(item, delta: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(item.quantity <= 1 ? MD3Theme.error : MD3Theme.onSurfaceVariant)
                }
                .buttonStyle(.plain)

                Text("\(item.quantity)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .frame(minWidth: 32)
                    .monospacedDigit()

                Button {
                    adjustQuantity(item, delta: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(MD3Theme.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                if item.foilQuantity > 0 {
                    Text("\(item.foilQuantity) foil")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Adjusts a collection item's quantity by `delta` (+1 or -1).
    /// If the new quantity would be ≤ 0, deletes the item. Also caps
    /// foil quantity so it never exceeds total quantity.
    private func adjustQuantity(_ item: CollectionItem, delta: Int) {
        let newQty = item.quantity + delta
        if newQty <= 0 {
            try? deckRepository.deleteCollectionItem(item)
        } else {
            let newFoil = min(item.foilQuantity, newQty)
            try? deckRepository.setCollectionQuantity(
                item,
                quantity: newQty,
                foilQuantity: newFoil
            )
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        reload()
    }

    /// Computes the percentage change from the at-add price snapshot to
    /// the current Scryfall USD price. Returns nil if either side is
    /// unknown or the change is < 5%.
    private func priceChange(item: CollectionItem, currentUSD: Double?) -> (label: String, isUp: Bool)? {
        guard let currentUSD,
              let snapshot = item.priceAtAddUSD,
              snapshot > 0 else { return nil }
        let percent = (currentUSD - snapshot) / snapshot * 100
        if abs(percent) < 5 { return nil }
        let arrow = percent > 0 ? "↑" : "↓"
        let label = String(format: "%@ %.0f%%", arrow, abs(percent))
        return (label: label, isUp: percent > 0)
    }

    // MARK: - Actions

    private func reload() {
        items = (try? deckRepository.fetchCollection()) ?? []
    }

}
