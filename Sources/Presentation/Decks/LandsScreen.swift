import SwiftUI

/// Browse curated card lists — Lands and cEDH Staples. Each category
/// opens a detail view with list/visual toggle, where every card is
/// tappable and shows owned quantity from the user's collection.
struct LandsScreen: View {

    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var dynamicReservedList: [LandCategory] = []
    @State private var dynamicSecretLair: [LandCategory] = []
    @State private var dynamicModern: [LandCategory] = []
    @State private var dynamicLegacy: [LandCategory] = []
    @State private var dynamicPioneer: [LandCategory] = []
    @State private var dynamicVintage: [LandCategory] = []
    @State private var dynamicPauper: [LandCategory] = []
    @State private var dynamicStandard: [LandCategory] = []
    @State private var dynamicPremodern: [LandCategory] = []
    @State private var searchText: String = ""
    @State private var dynamicLoaded: Bool = false

    /// All sections with their categories for search.
    private var allSections: [(name: String, categories: [LandCategory])] {
        [
            ("Lands", LandLists.all),
            ("Collectible Lands", CollectibleLands.all),
            ("Secret Lair Lands", dynamicSecretLair.isEmpty ? SecretLairLands.all : dynamicSecretLair),
            ("Reserved List", dynamicReservedList.isEmpty ? ReservedList.all : dynamicReservedList),
            ("Modern Staples", ModernStaples.all),
            ("Legacy Staples", LegacyStaples.all),
            ("Pioneer Staples", PioneerStaples.all),
            ("Vintage Staples", VintageStaples.all),
            ("Pauper Staples", PauperStaples.all),
            ("Standard Staples", StandardStaples.all),
            ("Premodern Staples", PremodernStaples.all),
            ("Modern Most-Played", dynamicModern),
            ("Legacy Most-Played", dynamicLegacy),
            ("Pioneer Most-Played", dynamicPioneer),
            ("Vintage Most-Played", dynamicVintage),
            ("Pauper Most-Played", dynamicPauper),
            ("Standard Most-Played", dynamicStandard),
            ("Premodern Most-Played", dynamicPremodern),
            ("cEDH Staples", CEDHStaples.all),
            ("Japanese Collectibles", JapaneseCollectibles.all),
        ]
    }

    /// Search results: (sectionName, categoryName, cardName) tuples.
    private var searchResults: [(section: String, category: String, categoryObj: LandCategory, categories: [LandCategory])] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        var results: [(section: String, category: String, categoryObj: LandCategory, categories: [LandCategory])] = []
        for section in allSections {
            for category in section.categories {
                let matchesCategory = category.name.lowercased().contains(query)
                let matchesCard = category.cardNames.contains { $0.lowercased().contains(query) }
                if matchesCategory || matchesCard {
                    results.append((section: section.name, category: category.name, categoryObj: category, categories: section.categories))
                }
            }
        }
        return results
    }

    var body: some View {
        List {
            if !searchText.isEmpty {
                if searchResults.isEmpty {
                    Section {
                        Text("No results for \"\(searchText)\"")
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                } else {
                    ForEach(Array(Set(searchResults.map(\.section))).sorted(), id: \.self) { sectionName in
                        Section(sectionName) {
                            ForEach(searchResults.filter { $0.section == sectionName }, id: \.categoryObj.id) { result in
                                categoryRow(result.categoryObj, in: result.categories)
                            }
                        }
                    }
                }
            } else {
            Section("Price Lists") {
                NavigationLink {
                    TopBasicLandsScreen(
                        cardRepository: cardRepository,
                        deckRepository: deckRepository
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Top 100 Basic Lands")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(MD3Theme.onSurface)
                            Text("Most expensive basic lands by price")
                                .font(.caption2)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Lands") {
                ForEach(LandLists.all) { category in
                    categoryRow(category, in: LandLists.all)
                }
            }
            Section("Collectible Lands") {
                ForEach(CollectibleLands.all) { category in
                    categoryRow(category, in: CollectibleLands.all)
                }
            }
            Section("Secret Lair Lands") {
                let slCategories = dynamicSecretLair.isEmpty ? SecretLairLands.all : dynamicSecretLair
                ForEach(slCategories) { category in
                    categoryRow(category, in: slCategories)
                }
            }
            Section("Reserved List") {
                let rlCategories = dynamicReservedList.isEmpty ? ReservedList.all : dynamicReservedList
                ForEach(rlCategories) { category in
                    categoryRow(category, in: rlCategories)
                }
            }
            // Staples: curated essential cards (timeless, rarely change)
            Section("Modern Staples") {
                ForEach(ModernStaples.all) { c in categoryRow(c, in: ModernStaples.all) }
            }
            Section("Legacy Staples") {
                ForEach(LegacyStaples.all) { c in categoryRow(c, in: LegacyStaples.all) }
            }
            Section("Pioneer Staples") {
                ForEach(PioneerStaples.all) { c in categoryRow(c, in: PioneerStaples.all) }
            }
            Section("Vintage Staples") {
                ForEach(VintageStaples.all) { c in categoryRow(c, in: VintageStaples.all) }
            }
            Section("Pauper Staples") {
                ForEach(PauperStaples.all) { c in categoryRow(c, in: PauperStaples.all) }
            }
            Section("Standard Staples") {
                ForEach(StandardStaples.all) { c in categoryRow(c, in: StandardStaples.all) }
            }
            Section("Premodern Staples") {
                ForEach(PremodernStaples.all) { c in categoryRow(c, in: PremodernStaples.all) }
            }
            // Most-Played: dynamic from MTGTop8 tournaments (changes with meta)
            if !dynamicModern.isEmpty || !dynamicLegacy.isEmpty || !dynamicPioneer.isEmpty {
                mostPlayedSection("Modern Most-Played", categories: dynamicModern)
                mostPlayedSection("Legacy Most-Played", categories: dynamicLegacy)
                mostPlayedSection("Pioneer Most-Played", categories: dynamicPioneer)
                mostPlayedSection("Vintage Most-Played", categories: dynamicVintage)
                mostPlayedSection("Pauper Most-Played", categories: dynamicPauper)
                mostPlayedSection("Standard Most-Played", categories: dynamicStandard)
                mostPlayedSection("Premodern Most-Played", categories: dynamicPremodern)
            }
            Section("cEDH Staples") {
                ForEach(CEDHStaples.all) { category in
                    categoryRow(category, in: CEDHStaples.all)
                }
            }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search cards or categories")
        .task {
            guard !dynamicLoaded else { return }
            let service = DynamicListService.shared
            dynamicReservedList = await service.reservedList()
            dynamicSecretLair = await service.secretLairDrops()
            // Load dynamic format staples from MTGTop8 aggregation cache
            dynamicModern = await service.formatStaples(formatName: "Modern")
            dynamicLegacy = await service.formatStaples(formatName: "Legacy")
            dynamicPioneer = await service.formatStaples(formatName: "Pioneer")
            dynamicVintage = await service.formatStaples(formatName: "Vintage")
            dynamicPauper = await service.formatStaples(formatName: "Pauper")
            dynamicStandard = await service.formatStaples(formatName: "Standard")
            dynamicPremodern = await service.formatStaples(formatName: "Premodern")
            dynamicLoaded = true
        }
    }

    @ViewBuilder
    private func mostPlayedSection(_ title: String, categories: [LandCategory]) -> some View {
        if !categories.isEmpty {
            Section(title) {
                ForEach(categories) { category in
                    categoryRow(category, in: categories)
                }
            }
        }
    }

    private func categoryRow(_ category: LandCategory, in categories: [LandCategory]) -> some View {
        let index = categories.firstIndex(where: { $0.id == category.id }) ?? 0
        return NavigationLink {
            LandSectionPagerView(
                categories: categories,
                initialIndex: index,
                cardRepository: cardRepository,
                deckRepository: deckRepository
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MD3Theme.primary)
                    .frame(width: 32)
                Text(category.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Section Pager View

/// Horizontal pager that wraps category detail views, letting the user
/// swipe left/right to browse adjacent categories within a section.
struct LandSectionPagerView: View {

    let categories: [LandCategory]
    let initialIndex: Int
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var currentIndex: Int = 0
    @State private var viewMode: ViewMode = .list
    @State private var sortByPrice: Bool = false

    enum ViewMode: String, CaseIterable, Hashable {
        case list, grid
        var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                LandCategoryDetailView(
                    category: category,
                    viewMode: viewMode,
                    sortByPrice: sortByPrice,
                    cardRepository: cardRepository,
                    deckRepository: deckRepository
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .onAppear { currentIndex = initialIndex }
        .navigationTitle(categories.indices.contains(currentIndex) ? categories[currentIndex].name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    sortByPrice.toggle()
                } label: {
                    Image(systemName: sortByPrice ? "dollarsign.circle.fill" : "dollarsign.circle")
                        .foregroundStyle(sortByPrice ? MD3Theme.primary : MD3Theme.onSurfaceVariant)
                }
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
        }
    }
}

// MARK: - Category Detail View

/// Shows all cards in a land category with list/visual toggle.
/// Each card is resolved via `CardResolver` (honoring the user's
/// Default Printing setting) and tappable -> `CardDetailView`.
/// Categories with `setCodes` show ALL printings from those sets.
struct LandCategoryDetailView: View {

    /// In-memory cache: resolved cards persist across navigation within session.
    nonisolated(unsafe) private static var cardCache: [String: [String: [Card]]] = [:]

    /// Disk cache directory for persisting resolved cards across app restarts.
    private static var diskCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CardListCache", isDirectory: true)
    }

    /// Save resolved cards for a category to disk.
    private static func saveToDisk(categoryID: String, cards: [String: [Card]]) {
        let dir = diskCacheURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(categoryID).json")
        // Encode as [[scryfallID, name, setCode, setName, collectorNumber, imageURL, priceUSD]]
        var entries: [[String]] = []
        for (_, cardList) in cards {
            for card in cardList {
                let img = card.imageURIs["normal"] ?? card.imageURIs["small"] ?? ""
                entries.append([card.scryfallID, card.name, card.set.code, card.set.name,
                               card.collectorNumber, img, card.prices.usd ?? ""])
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: entries) {
            try? data.write(to: file)
        }
    }

    /// Load resolved card scryfallIDs from disk cache (for quick DB lookup).
    private static func loadFromDisk(categoryID: String) -> [String]? {
        let file = diskCacheURL.appendingPathComponent("\(categoryID).json")
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String]] else {
            return nil
        }
        return entries.map { $0[0] } // scryfallIDs
    }

    let category: LandCategory
    let viewMode: LandSectionPagerView.ViewMode
    let sortByPrice: Bool
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    /// Resolved cards keyed by card name. Each name may have multiple
    /// printings when the category specifies `setCodes`.
    @State private var resolvedCards: [String: [Card]] = [:]
    @State private var ownedByName: [String: Int] = [:]
    @State private var ownedDetails: [String: [(setCode: String, setName: String, quantity: Int)]] = [:]
    /// Per-printing ownership for accurate badges on multi-variant categories.
    @State private var ownedByScryfallID: [String: Int] = [:]

    /// All resolved cards flattened in display order.
    private var sortedCards: [Card] {
        let flat = category.cardNames.flatMap { name -> [Card] in
            (resolvedCards[name] ?? []).sorted { $0.collectorNumber < $1.collectorNumber }
        }
        guard sortByPrice else { return flat }
        return flat.sorted { a, b in
            let pa = Double(a.prices.usd ?? "") ?? -1
            let pb = Double(b.prices.usd ?? "") ?? -1
            return pa > pb
        }
    }

    private var allResolved: Bool {
        category.cardNames.allSatisfy { resolvedCards[$0] != nil }
    }

    var body: some View {
        Group {
            switch viewMode {
            case .list:
                listBody
            case .grid:
                gridBody
            }
        }
        .task {
            // 1. In-memory cache (fastest)
            if let cached = Self.cardCache[category.id] {
                resolvedCards = cached
            }
            // 2. Ownership data
            ownedByName = (try? deckRepository.ownedQuantitiesByName()) ?? [:]
            ownedDetails = (try? deckRepository.ownedDetailsByName()) ?? [:]
            ownedByScryfallID = (try? deckRepository.ownedQuantitiesByScryfallID()) ?? [:]
            // 3. If not in memory, try disk cache → resolve → save
            if resolvedCards.isEmpty {
                await resolveAll()
                Self.cardCache[category.id] = resolvedCards
                // Persist to disk for next app launch
                Self.saveToDisk(categoryID: category.id, cards: resolvedCards)
            }
        }
    }

    // MARK: - Resolution

    private func resolveAll() async {
        for name in category.cardNames {
            guard resolvedCards[name] == nil else { continue }

            if !category.setCodes.isEmpty {
                // Fast path: direct indexed lookup by (name + setCode)
                // instead of searching all printings then filtering
                var allFiltered: [Card] = []
                for setCode in category.setCodes {
                    let variants = (try? await cardRepository.findVariants(name: name, setCode: setCode)) ?? []
                    allFiltered.append(contentsOf: variants)
                }
                if !category.collectorNumbers.isEmpty {
                    allFiltered = allFiltered.filter { category.collectorNumbers.contains($0.collectorNumber) }
                }
                if let artist = category.artistFilter {
                    allFiltered = allFiltered.filter { $0.artist?.contains(artist) == true }
                }
                if !allFiltered.isEmpty {
                    resolvedCards[name] = allFiltered
                    continue
                }
                // Fallback: slow search if fast path found nothing
                if let printings = try? await cardRepository.findAllPrintings(name: name) {
                    var filtered = printings.filter { category.setCodes.contains($0.set.code) }
                    if !category.collectorNumbers.isEmpty {
                        filtered = filtered.filter { category.collectorNumbers.contains($0.collectorNumber) }
                    }
                    if let artist = category.artistFilter {
                        filtered = filtered.filter { $0.artist?.contains(artist) == true }
                    }
                    if !filtered.isEmpty {
                        resolvedCards[name] = filtered
                        continue
                    }
                }
            }

            // For single-card categories (e.g., Wastes), show ALL printings
            if category.cardNames.count == 1 {
                if let allPrintings = try? await cardRepository.findAllPrintings(name: name),
                   !allPrintings.isEmpty {
                    resolvedCards[name] = allPrintings
                    continue
                }
            }

            // Fallback: standard resolution via CardResolver
            let resolver = CardResolver(cardRepository: cardRepository)
            if let card = await resolver.resolve(name: name) {
                resolvedCards[name] = [card]
            }
        }
    }

    // MARK: - Ownership

    private enum OwnershipStatus {
        case exactMatch(Int)
        case differentSet([(setName: String, quantity: Int)])
        case notOwned
    }

    private func ownershipStatus(for card: Card) -> OwnershipStatus {
        let name = card.name
        let details = ownedDetails[name] ?? []

        if !category.setCodes.isEmpty {
            // Collectible lands: check this exact printing by scryfallID
            let exactQty = ownedByScryfallID[card.scryfallID] ?? 0
            return exactQty > 0 ? .exactMatch(exactQty) : .notOwned
        }

        // Normal lists: check if owned in any printing
        let totalOwned = ownedByName[name] ?? 0
        guard totalOwned > 0 else { return .notOwned }

        let matchingQty = details
            .filter { $0.setCode == card.set.code }
            .reduce(0) { $0 + $1.quantity }
        if matchingQty > 0 { return .exactMatch(matchingQty) }

        let setDetails = details.map { (setName: $0.setName, quantity: $0.quantity) }
        return .differentSet(setDetails)
    }

    private static let attributionText = "Sources: MTG Wiki (mtg.fandom.com), Scryfall, Card Kingdom Blog, MTGGoldfish, Draftsim, CoolStuffInc, ManaGathering, Magic Librarities, Wikipedia."

    // MARK: - List

    private var listBody: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.description)
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                    Text(Self.attributionText)
                        .font(.system(size: 8))
                        .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.6))
                }
                .listRowBackground(Color.clear)
            }
            Section("\(sortedCards.count) cards") {
                let cards = sortedCards
                ForEach(Array(cards.enumerated()), id: \.element.scryfallID) { index, card in
                    NavigationLink {
                        CardListPagerView(
                            cards: cards,
                            initialIndex: index,
                            cardRepository: cardRepository,
                            deckRepository: deckRepository
                        )
                    } label: {
                        listRow(card: card)
                    }
                }
                if !allResolved {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading\u{2026}")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func listRow(card: Card) -> some View {
        let status = ownershipStatus(for: card)
        return HStack(spacing: 12) {
            // Owned quantity badge
            switch status {
            case .exactMatch(let qty):
                Text("\(qty)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.green)
                    .clipShape(Circle())
            case .differentSet:
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.orange)
                    .clipShape(Circle())
            case .notOwned:
                Circle()
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text("0")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)
                    if let manaCost = card.manaCost, !manaCost.isEmpty {
                        ManaCostView(cost: manaCost, size: 12)
                    }
                }
                Text("\(card.setNameWithYear) \u{00B7} #\(card.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                if case .differentSet(let sets) = status {
                    let summary = sets.map { "\($0.quantity)x \($0.setName)" }.joined(separator: ", ")
                    Text("Owned: \(summary)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let usd = card.prices.usd {
                Text("$\(usd)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.primary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Grid

    private var gridBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.description)
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                    Text(Self.attributionText)
                        .font(.system(size: 8))
                        .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.6))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                let cards = sortedCards
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(Array(cards.enumerated()), id: \.element.scryfallID) { index, card in
                        NavigationLink {
                            CardListPagerView(
                                cards: cards,
                                initialIndex: index,
                                cardRepository: cardRepository,
                                deckRepository: deckRepository
                            )
                        } label: {
                            gridCardLabel(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                if !allResolved {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                }

                Color.clear.frame(height: 24)
            }
        }
        .background(MD3Theme.background)
    }

    private func gridCardLabel(card: Card) -> some View {
        let status = ownershipStatus(for: card)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let urlString = card.imageURIs["small"]
                       ?? card.imageURIs["normal"]
                       ?? card.imageURIs["large"],
                   let url = URL(string: urlString) {
                    CachedPhaseImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(63.0 / 88.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        default:
                            gridPlaceholder(card.name)
                        }
                    }
                } else {
                    gridPlaceholder(card.name)
                }
                // Owned badge
                switch status {
                case .exactMatch(let qty):
                    Text("\(qty)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.green)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                case .differentSet:
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.orange)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                case .notOwned:
                    EmptyView()
                }
            }
            Text(card.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MD3Theme.onSurface)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private func gridPlaceholder(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(MD3Theme.surfaceVariant)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .overlay(
                Text(name)
                    .font(.system(size: 8))
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }
}

// MARK: - Card Pager View

/// Horizontal paging view that wraps `CardDetailView` instances,
/// letting the user swipe left/right to browse cards in a land category.
struct CardListPagerView: View {

    let cards: [Card]
    let initialIndex: Int
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var currentIndex: Int = 0

    /// Only render the current card ± 1 neighbor to avoid
    /// spawning dozens of CardDetailViews (each fires network
    /// calls for PH stores, rulings, MTGTop8, etc.).
    private var visibleWindow: [(index: Int, card: Card)] {
        guard !cards.isEmpty else { return [] }
        let lo = max(0, currentIndex - 1)
        let hi = min(cards.count - 1, currentIndex + 1)
        return (lo...hi).map { (index: $0, card: cards[$0]) }
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(cards.indices, id: \.self) { index in
                if visibleWindow.contains(where: { $0.index == index }) {
                    CardDetailView(
                        card: cards[index],
                        repository: cardRepository,
                        deckRepository: deckRepository,
                        onScanAnother: {}
                    )
                    .tag(index)
                } else {
                    // Lightweight placeholder for distant pages — keeps
                    // the TabView pagination working without the cost
                    // of a full CardDetailView.
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .onAppear { currentIndex = initialIndex }
        .navigationTitle(cards.indices.contains(currentIndex) ? cards[currentIndex].name : "")
        .navigationBarTitleDisplayMode(.inline)
    }
}
