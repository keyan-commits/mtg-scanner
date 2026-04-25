import SwiftUI

/// Dashboard home screen. Shows live stats from the user's data, a hero
/// CTA for the scanner, recent decks as a horizontal scroller, and a
/// "More" section with the less-frequently-used tools (Classic Decks,
/// Help, etc.).
struct HomeView: View {

    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol
    @Binding var homeTabRetapped: Bool
    let onScanTap: () -> Void

    @State private var stats: HomeStats = .empty
    @State private var isLoadingStats: Bool = true
    @State private var recentDecks: [DeckList] = []
    /// Cached `art_crop` URL per deck.id for the signature card background.
    @State private var deckArtURLs: [UUID: URL] = [:]
    @State private var iconPickerDeck: DeckList?
    @State private var searchText: String = ""
    @State private var searchResults: [Card] = []
    @State private var archetypeResults: [ArchetypeSearchResult] = []
    @State private var isSearchingActive: Bool = false
    @State private var searchScope: SearchScope = .cards
    @State private var isLoadingDecks: Bool = false
    /// Top sought-after cards for the home section. Empty until the
    /// pre-warm has aggregated at least 2 curated major archetypes.
    @State private var soughtAfterCards: [SoughtAfterCard] = []
    @State private var hotCards: [Card] = []  // Price movers (seller perspective)
    /// Resolved Card per name (via the user's printing strategy) so
    /// the sought-after row can render images.
    @State private var soughtAfterResolved: [String: Card] = [:]
    /// Progress of the curated-archetype pre-warm. Nil when not running.
    @State private var soughtAfterWarmupProgress: (loaded: Int, total: Int)?
    private let soughtAfterService = SoughtAfterCardsService()

    /// Cards vs Decks scope picker for the home search bar. Selecting
    /// a scope filters which kind of result is rendered — the two
    /// search corpora are kept entirely separate per user request.
    enum SearchScope: String, CaseIterable, Identifiable {
        case cards = "Cards"
        case decks = "Decks"
        var id: String { rawValue }
    }

    private let archetypeSearch = ArchetypeSearchService()

    struct HomeStats {
        let deckCount: Int
        let collectionUniques: Int
        let collectionCopies: Int
        let orderCount: Int
        let pendingOrders: Int
        let spentByCurrency: [String: Double]

        static let empty = HomeStats(
            deckCount: 0,
            collectionUniques: 0,
            collectionCopies: 0,
            orderCount: 0,
            pendingOrders: 0,
            spentByCurrency: [:]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isSearchingActive {
                    searchResultsView
                } else {
                    greeting
                    statsCard
                    formatStaplesSection
                    priceMoversSection
                    collectionHighlightsSection
                    heroScanCard
                    if !recentDecks.isEmpty {
                        recentDecksSection
                    }
                    quickActionsSection
                    moreSection
                    Color.clear.frame(height: 24)
                }
            }
            .padding(20)
        }
        .background(MD3Theme.background)
        .navigationTitle("MTG Keyan")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            isPresented: $isSearchingActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: searchScope == .cards ? "Search cards" : "Search decks (e.g. Affinity)"
        )
        .searchScopes($searchScope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .task(id: searchText) {
            await performSearch()
        }
        .task(id: searchScope) {
            // Re-run when the user flips Cards ↔ Decks so the active
            // results section reflects the current query.
            await performSearch()
        }
        .onChange(of: homeTabRetapped) { _, _ in
            // User tapped Home tab while already on Home → dismiss search
            if isSearchingActive {
                isSearchingActive = false
            }
        }
        .onChange(of: isSearchingActive) { _, isActive in
            if !isActive {
                searchText = ""
                searchResults = []
                archetypeResults = []
            }
        }
        .task {
            await reloadAsync()
        }
        .task {
            await loadSoughtAfterCards()
        }
        .task {
            await loadDeckArt()
        }
        .task {
            await loadHotCards()
        }
        .sheet(item: $iconPickerDeck) { deck in
            ChooseDeckIconSheet(
                deck: deck,
                deckRepository: deckRepository,
                cardRepository: cardRepository
            ) {
                iconPickerDeck = nil
                deckArtURLs[deck.id] = nil
                Task { await loadDeckArt() }
            }
        }
    }

    /// Lazily fetches the `art_crop` URL for each recent deck's signature
    /// card. Cached by deck.id so swapping back to Home doesn't refetch.
    private func loadDeckArt() async {
        for deck in recentDecks.prefix(6) {
            if deckArtURLs[deck.id] != nil { continue }
            guard let signature = deck.signatureCard else { continue }
            if let card = try? await cardRepository.fetchCard(
                set: signature.setCode,
                collectorNumber: signature.collectorNumber
            ) {
                let urlString = card.imageURIs["art_crop"]
                    ?? card.imageURIs["normal"]
                    ?? card.imageURIs["large"]
                if let urlString, let url = URL(string: urlString) {
                    deckArtURLs[deck.id] = url
                }
            }
        }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchResultsView: some View {
        switch searchScope {
        case .cards:
            cardScopeView
        case .decks:
            deckScopeView
        }
    }

    @ViewBuilder
    private var cardScopeView: some View {
        if searchResults.isEmpty {
            searchEmptyState(message: searchText.count < 2 ? "Type at least 2 characters" : "No cards found")
        } else {
            cardResultsSection
        }
    }

    @ViewBuilder
    private var deckScopeView: some View {
        if isLoadingDecks && archetypeResults.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading decks…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else if archetypeResults.isEmpty {
            searchEmptyState(message: searchText.count < 2 ? "Type at least 2 characters" : "No decks found")
        } else {
            archetypeResultsSection
                .refreshable {
                    await refreshDecks()
                }
        }
    }

    private func searchEmptyState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var archetypeResultsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Decks · \(archetypeResults.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .textCase(.uppercase)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(Array(archetypeResults.enumerated()), id: \.element.id) { idx, result in
                    NavigationLink {
                        ArchetypeDecksView(
                            archetype: result.name,
                            format: result.format,
                            source: result.source,
                            maxPlacement: 10,
                            cardRepository: cardRepository,
                            deckRepository: deckRepository
                        )
                    } label: {
                        archetypeResultRow(result)
                    }
                    .buttonStyle(.plain)
                    if idx < archetypeResults.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )
        }
    }

    private var cardResultsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cards · \(searchResults.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .textCase(.uppercase)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(Array(searchResults.enumerated()), id: \.element.id) { idx, card in
                    NavigationLink {
                        CardListPagerView(
                            cards: searchResults,
                            initialIndex: idx,
                            cardRepository: cardRepository,
                            deckRepository: deckRepository
                        )
                    } label: {
                        searchResultRow(card)
                    }
                    .buttonStyle(.plain)
                    if idx < searchResults.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )
        }
    }

    private func archetypeResultRow(_ result: ArchetypeSearchResult) -> some View {
        HStack(spacing: 12) {
            // Stacked-cards glyph to distinguish deck rows from card rows
            RoundedRectangle(cornerRadius: 8)
                .fill(MD3Theme.primaryContainer)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MD3Theme.primary)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(result.format)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MD3Theme.primaryContainer)
                        .clipShape(Capsule())
                    Text(result.era)
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private func searchResultRow(_ card: Card) -> some View {
        HStack(spacing: 12) {
            // Tiny art-crop thumbnail
            if let urlString = card.imageURIs["art_crop"]
                                ?? card.imageURIs["small"]
                                ?? card.imageURIs["normal"],
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        searchThumbPlaceholder
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                searchThumbPlaceholder
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)
                    if let manaCost = card.manaCost, !manaCost.isEmpty {
                        ManaCostView(cost: manaCost, size: 12)
                    }
                }
                Text("\(card.setNameWithYear) · #\(card.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    private var searchThumbPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(MD3Theme.surfaceVariant)
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: "rectangle.stack")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    /// Debounced search. Runs only the side that matches the active
    /// `searchScope` so card and deck searches stay strictly separate
    /// (the user explicitly asked for these to not be mixed).
    ///
    /// Cards (local Scryfall DB): returns every matching printing —
    /// does NOT dedupe by name, so "Vampiric Tutor" shows the Visions,
    /// Eternal Masters, Dominaria Remastered etc. printings as separate
    /// rows. Sorted oldest-first within each name.
    ///
    /// Decks: searches both `ClassicArchetypes` (offline catalog) and
    /// MTGTop8's per-format archetype index (cached for 7 days, lazily
    /// fetched). Tapping a result opens `ArchetypeDecksView` filtered
    /// to top-10 finishes.
    private func performSearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            archetypeResults = []
            isLoadingDecks = false
            return
        }
        // 250ms debounce so we don't fire on every keystroke.
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }
        guard trimmed == searchText.trimmingCharacters(in: .whitespaces) else { return }

        switch searchScope {
        case .cards:
            await runCardSearch(trimmed)
        case .decks:
            await runDeckSearch(trimmed)
        }
    }

    /// Normalizes smart quotes/curly apostrophes to plain ASCII so
    /// "Mishra's Factory" typed with iOS smart punctuation matches
    /// the DB's plain-apostrophe "Mishra's Factory".
    private static func normalizeQuotes(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2018}", with: "'")  // left single quote
         .replacingOccurrences(of: "\u{2019}", with: "'")  // right single quote (iOS default)
         .replacingOccurrences(of: "\u{201C}", with: "\"") // left double quote
         .replacingOccurrences(of: "\u{201D}", with: "\"") // right double quote
    }

    private func runCardSearch(_ query: String) async {
        let normalized = Self.normalizeQuotes(query)
        guard let cards = try? await cardRepository.searchCards(query: normalized) else {
            searchResults = []
            return
        }
        let sorted = cards.sorted { a, b in
            if a.name != b.name { return a.name < b.name }
            return (a.releasedAt ?? "9999") < (b.releasedAt ?? "9999")
        }
        searchResults = Array(sorted.prefix(80))
    }

    private func runDeckSearch(_ query: String) async {
        isLoadingDecks = true
        defer { isLoadingDecks = false }
        archetypeResults = await archetypeSearch.search(query)
    }

    /// Pull-to-refresh handler for the deck results section. Forces the
    /// online MTGTop8 archetype index to refetch (ignoring TTL), then
    /// re-runs the current search.
    private func refreshDecks() async {
        await archetypeSearch.refreshOnlineIndex()
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        archetypeResults = await archetypeSearch.search(trimmed)
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeBasedGreeting)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Text("What are you building today?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(MD3Theme.onBackground)
        }
    }

    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Welcome back"
        }
    }

    // MARK: - Stats card

    @ViewBuilder
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your Workshop")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.8))
                    .textCase(.uppercase)
                Spacer()
                if isLoadingStats {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(MD3Theme.onPrimaryContainer.opacity(0.6))
                }
            }
            HStack(alignment: .top, spacing: 0) {
                statTile(value: "\(stats.deckCount)", label: "Decks", icon: "rectangle.stack.fill")
                Divider().frame(height: 38)
                statTile(value: "\(stats.collectionUniques)", label: "Owned", icon: "tray.full.fill")
                Divider().frame(height: 38)
                statTile(value: "\(stats.orderCount)", label: "Orders", icon: "shippingbox.fill")
            }
            if let spentLabel = CurrencyTotals.format(stats.spentByCurrency) {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                        .font(.caption2)
                    Text("Spent \(spentLabel)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.85))
                .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [MD3Theme.primaryContainer, MD3Theme.primaryContainer.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.7))
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(MD3Theme.onPrimaryContainer)
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sought-after cards

    /// Top 10 most-played cards across the user's browsed major
    /// archetypes. Empty until the user has visited at least one
    /// archetype detail page (which populates the aggregation cache).
    /// Each image is resolved through the user's Default Printing
    /// setting via `CardResolver`.
    // MARK: - Format Staples (Player)

    @ViewBuilder
    private var formatStaplesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink {
                SoughtAfterCardsScreen(
                    cardRepository: cardRepository,
                    deckRepository: deckRepository
                )
            } label: {
                HStack {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Format Staples")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onBackground)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("Most-played cards across competitive archetypes")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            if !soughtAfterCards.isEmpty {
                VStack(spacing: 0) {
                    ForEach(soughtAfterCards.prefix(5)) { entry in
                        stapleRow(entry)
                        if entry.id != soughtAfterCards.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                .padding(12)
                .background(MD3Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if soughtAfterWarmupProgress != nil {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading archetype data...")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
        }
    }

    private func stapleRow(_ entry: SoughtAfterCard) -> some View {
        let resolved = soughtAfterResolved[entry.cardName]
        return HStack(spacing: 8) {
            Text(entry.cardName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MD3Theme.onSurface)
                .lineLimit(1)
            Spacer()
            Text("in \(entry.archetypeCount) archetypes")
                .font(.system(size: 10))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            if let usd = resolved?.prices.usd {
                Text("$\(usd)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MD3Theme.primary)
            }
        }
        .padding(.vertical, 4)
        .task { await resolveSoughtAfter(name: entry.cardName) }
    }

    // MARK: - Price Movers (Seller)

    @ViewBuilder
    private var priceMoversSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("Price Movers (24h)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onBackground)
                Spacer()
            }

            Text("Biggest price changes in the last 24 hours")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            if !hotCards.isEmpty {
                VStack(spacing: 0) {
                    ForEach(hotCards.prefix(5)) { card in
                        NavigationLink {
                            CardDetailView(
                                card: card,
                                repository: cardRepository,
                                deckRepository: deckRepository,
                                onScanAnother: {}
                            )
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(card.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(MD3Theme.onSurface)
                                        .lineLimit(1)
                                    Text(card.setNameWithYear)
                                        .font(.system(size: 10))
                                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let change = card.prices.priceChangePercent {
                                    let isUp = change > 0
                                    Text("\(isUp ? "↑" : "↓") \(String(format: "%.0f", abs(change)))%")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(isUp ? .green : .red)
                                }
                                if let usd = card.prices.usd {
                                    Text("$\(usd)")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(MD3Theme.primary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                        if card.id != hotCards.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                .padding(12)
                .background(MD3Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if PriceRefreshService.shared?.isRefreshing == true {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Updating prices…")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MD3Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Price movers appear after the second daily price refresh")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.6))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MD3Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Collection Highlights (Collector)

    @ViewBuilder
    private var collectionHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "diamond.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text("Collection Highlights")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onBackground)
                Spacer()
            }

            let preferred = LocalCurrency.current
            let totalUSD = UserDefaults.standard.double(forKey: "collectionCachedValueUSD")

            VStack(spacing: 8) {
                HStack {
                    Text("Estimated Value")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                    Spacer()
                    if totalUSD > 0, let converted = CurrencyService.shared.convert(totalUSD, to: preferred) {
                        Text(LocalCurrency.format(converted, currency: preferred))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(MD3Theme.onSurface)
                    } else {
                        Text("—")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
                    }
                }
                Divider()
                HStack {
                    Label("\(stats.collectionUniques) unique", systemImage: "rectangle.stack")
                    Spacer()
                    Label("\(stats.collectionCopies) copies", systemImage: "square.on.square")
                }
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            .padding(12)
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func soughtAfterWarmupView(loaded: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Loading global archetype data… \(loaded)/\(total)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            ProgressView(value: Double(loaded), total: Double(total))
                .progressViewStyle(.linear)
                .tint(MD3Theme.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var soughtAfterPlaceholderView: some View {
        Text("Browse a major archetype or pull to refresh to populate this list.")
            .font(.caption2)
            .foregroundStyle(MD3Theme.onSurfaceVariant)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func soughtAfterCardView(_ entry: SoughtAfterCard, index: Int) -> some View {
        let resolved = soughtAfterResolved[entry.cardName]
        let allResolved = soughtAfterCards.compactMap { soughtAfterResolved[$0.cardName] }
        return Group {
            if let resolved {
                NavigationLink {
                    if allResolved.count > 1,
                       let pos = allResolved.firstIndex(where: { $0.scryfallID == resolved.scryfallID }) {
                        CardListPagerView(
                            cards: allResolved,
                            initialIndex: pos,
                            cardRepository: cardRepository,
                            deckRepository: deckRepository
                        )
                    } else {
                        CardDetailView(
                            card: resolved,
                            repository: cardRepository,
                            deckRepository: deckRepository,
                            onScanAnother: {}
                        )
                    }
                } label: {
                    soughtAfterCardLabel(entry: entry, card: resolved)
                }
                .buttonStyle(.plain)
            } else {
                soughtAfterCardLabel(entry: entry, card: nil)
                    .task { await resolveSoughtAfter(name: entry.cardName) }
            }
        }
    }

    @ViewBuilder
    private func soughtAfterCardLabel(entry: SoughtAfterCard, card: Card?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let card,
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
                            soughtAfterPlaceholder(name: entry.cardName)
                        }
                    }
                } else {
                    soughtAfterPlaceholder(name: entry.cardName)
                }
            }
            .frame(width: 88)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )
            Text(entry.cardName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(MD3Theme.onSurface)
                .lineLimit(1)
                .frame(width: 88, alignment: .leading)
            Text("\(entry.archetypeCount) deck\(entry.archetypeCount == 1 ? "" : "s")")
                .font(.system(size: 9))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .frame(width: 88, alignment: .leading)
        }
    }

    private func soughtAfterPlaceholder(name: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(MD3Theme.surfaceVariant)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .overlay(
                Text(name)
                    .font(.system(size: 9))
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    private func resolveSoughtAfter(name: String) async {
        guard soughtAfterResolved[name] == nil else { return }
        let resolver = CardResolver(cardRepository: cardRepository)
        if let card = await resolver.resolve(name: name) {
            soughtAfterResolved[name] = card
        }
    }

    private func loadHotCards() async {
        // Skip if price refresh hasn't completed yet (no previousPriceUSD data)
        guard PriceRefreshService.shared != nil else { return }
        let movers = (try? await cardRepository.fetchPriceMovers(limit: 10)) ?? []
        hotCards = movers
    }

    private func loadSoughtAfterCards() async {
        soughtAfterCards = await soughtAfterService.topCards(limit: 10)

        // Auto-populate from format staples when cache is empty
        if soughtAfterCards.isEmpty {
            soughtAfterCards = Array(soughtAfterService.seedFromStaples().prefix(10))
        }

        // Daily auto-refresh from MTGTop8 (background, non-blocking).
        // Skip on first launch — let the user explore the app first before
        // kicking off heavy network requests that compete with price refresh.
        let isFirstLaunch = UserDefaults.standard.string(forKey: "soughtAfterLastRefresh") == nil
        if !isFirstLaunch,
           soughtAfterService.needsDailyRefresh,
           soughtAfterWarmupProgress == nil {
            Task.detached(priority: .utility) {
                await self.prewarmSoughtAfter()
                self.soughtAfterService.markRefreshed()
            }
        }
    }

    private func prewarmSoughtAfter() async {
        soughtAfterWarmupProgress = (loaded: 0, total: 0)
        await soughtAfterService.prewarmCuratedMajors { loaded, total in
            soughtAfterWarmupProgress = (loaded, total)
            // Refresh the list incrementally so the user sees cards
            // appear as each archetype finishes warming.
            Task {
                let updated = await soughtAfterService.topCards(limit: 10)
                if !updated.isEmpty {
                    soughtAfterCards = updated
                }
            }
        }
        soughtAfterWarmupProgress = nil
        soughtAfterCards = await soughtAfterService.topCards(limit: 10)
    }

    // MARK: - Hero scan card

    private var heroScanCard: some View {
        Button {
            onScanTap()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Identify a card")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Live scan or pick from photos")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        MD3Theme.primary,
                        MD3Theme.primary.opacity(0.85),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: MD3Theme.primary.opacity(0.25), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent decks

    @ViewBuilder
    private var recentDecksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Decks")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(MD3Theme.onBackground)
                Spacer()
                NavigationLink {
                    DecksScreen(repository: deckRepository, cardRepository: cardRepository)
                } label: {
                    Text("See all")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MD3Theme.primary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentDecks.prefix(6)) { deck in
                        NavigationLink {
                            DeckDetailView(deck: deck, repository: deckRepository, cardRepository: cardRepository)
                        } label: {
                            recentDeckCard(deck)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                iconPickerDeck = deck
                            } label: {
                                Label("Choose Icon", systemImage: "photo.on.rectangle")
                            }
                        }
                    }
                }
            }
        }
    }

    private func recentDeckCard(_ deck: DeckList) -> some View {
        let total = deck.items.count
        let arrived = deck.items.filter { $0.status == .arrived }.count
        let progress: Double = total > 0 ? Double(arrived) / Double(total) : 0
        return ZStack(alignment: .topLeading) {
            // Art-crop background (or fallback solid surface).
            if let artURL = deckArtURLs[deck.id] {
                AsyncImage(url: artURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        MD3Theme.surface
                    }
                }
                .frame(width: 200, height: 150)
                .clipped()
            } else {
                MD3Theme.surface
                    .frame(width: 200, height: 150)
            }

            // Bottom-up dark gradient for legibility of overlaid text.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.0),
                    .init(color: .black.opacity(0.45), location: 0.45),
                    .init(color: .black.opacity(0.85), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 200, height: 150)

            // Foreground content.
            VStack(alignment: .leading, spacing: 0) {
                if let format = deck.format, !format.isEmpty {
                    Text(DeckFormat.from(stored: format).displayName.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text(deck.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
                    HStack(spacing: 6) {
                        Text("\(arrived)/\(total)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        if total > 0 {
                            Text("· \(Int(progress * 100))%")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.25))
                                .frame(height: 3)
                            Capsule()
                                .fill(Color.green)
                                .frame(width: geo.size.width * progress, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(14)
        }
        .frame(width: 200, height: 150, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(MD3Theme.outlineVariant, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    // MARK: - Quick actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(MD3Theme.onBackground)
            HStack(spacing: 10) {
                NavigationLink {
                    DecksScreen(repository: deckRepository, cardRepository: cardRepository)
                } label: {
                    quickAction(icon: "rectangle.stack.fill", label: "My Decks", color: .blue)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    ShoppingListScreen(deckRepository: deckRepository, cardRepository: cardRepository)
                } label: {
                    quickAction(icon: "cart.fill", label: "Shopping", color: .orange)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    OrdersScreen(repository: deckRepository)
                } label: {
                    quickAction(icon: "shippingbox.fill", label: "Orders", color: .green, badge: stats.pendingOrders)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    CollectionScreen(deckRepository: deckRepository, cardRepository: cardRepository)
                } label: {
                    quickAction(icon: "tray.full.fill", label: "Collection", color: .purple)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quickAction(icon: String, label: String, color: Color, badge: Int? = nil) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                }
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - More section

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Browse")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(MD3Theme.onBackground)
            VStack(spacing: 0) {
                NavigationLink {
                    ClassicDecksScreen(deckRepository: deckRepository, cardRepository: cardRepository)
                } label: {
                    moreRow(icon: "books.vertical.fill", title: "Classic Decks", subtitle: "Hand-curated decks across 30 years of Magic", color: .indigo)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
                NavigationLink {
                    ClassicDecksScreen(
                        deckRepository: deckRepository,
                        cardRepository: cardRepository,
                        archetypes: InQuestDecks.all,
                        title: "InQuest Killer Decks"
                    )
                } label: {
                    moreRow(icon: "magazine.fill", title: "InQuest Killer Decks", subtitle: "Iconic decklists from InQuest Magazine (1995-1998)", color: .orange)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
                NavigationLink {
                    BrowseArchetypesScreen(
                        cardRepository: cardRepository,
                        deckRepository: deckRepository
                    )
                } label: {
                    moreRow(icon: "sparkles", title: "Browse Archetypes", subtitle: "Major archetypes with intros, strategy, and live common cards", color: .cyan)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
                NavigationLink {
                    FormatsScreen(
                        cardRepository: cardRepository,
                        deckRepository: deckRepository
                    )
                } label: {
                    moreRow(icon: "rectangle.3.group.fill", title: "Formats", subtitle: "Browse every MTGTop8 archetype by format", color: .teal)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
                NavigationLink {
                    TopCardsScreen(
                        cardRepository: cardRepository,
                        deckRepository: deckRepository
                    )
                } label: {
                    moreRow(icon: "dollarsign.circle.fill", title: "Top Cards", subtitle: "Top 10 most expensive cards per expansion", color: .orange)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
                NavigationLink {
                    LandsScreen(
                        cardRepository: cardRepository,
                        deckRepository: deckRepository
                    )
                } label: {
                    moreRow(icon: "list.star", title: "Lists", subtitle: "Lands, cEDH staples — with collection tracking", color: .brown)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
                NavigationLink {
                    HelpScreen()
                } label: {
                    moreRow(icon: "questionmark.circle.fill", title: "How it works", subtitle: "Walkthrough of the deck and order workflow", color: .pink)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 64)
                NavigationLink {
                    SettingsScreen()
                } label: {
                    moreRow(icon: "gearshape.fill", title: "Settings", subtitle: "Display currency, exchange rates", color: .gray)
                }
                .buttonStyle(.plain)
            }
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )
        }
    }

    private func moreRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    // MARK: - Data

    private func reload() {
        let decks = (try? deckRepository.fetchAllDecks()) ?? []
        let allItems = (try? deckRepository.fetchAllItems()) ?? []
        let collection = (try? deckRepository.fetchCollection()) ?? []
        let orders = (try? deckRepository.fetchOrders()) ?? []
        let pendingOrders = orders.filter { order in
            order.items.contains { $0.status != .arrived }
        }.count

        var spent: [String: Double] = [:]
        for item in allItems {
            guard let price = item.pricePaid else { continue }
            let key = item.currency ?? "USD"
            spent[key, default: 0] += price
        }

        stats = HomeStats(
            deckCount: decks.count,
            collectionUniques: collection.count,
            collectionCopies: collection.reduce(0) { $0 + $1.quantity },
            orderCount: orders.count,
            pendingOrders: pendingOrders,
            spentByCurrency: spent
        )
        recentDecks = decks
    }

    /// Async wrapper so the heavy DB fetches don't block the main thread.
    private func reloadAsync() async {
        await Task.detached(priority: .userInitiated) { @Sendable in
            let decks = (try? self.deckRepository.fetchAllDecks()) ?? []
            let allItems = (try? self.deckRepository.fetchAllItems()) ?? []
            let collection = (try? self.deckRepository.fetchCollection()) ?? []
            let orders = (try? self.deckRepository.fetchOrders()) ?? []
            let pendingOrders = orders.filter { order in
                order.items.contains { $0.status != .arrived }
            }.count

            var spent: [String: Double] = [:]
            for item in allItems {
                guard let price = item.pricePaid else { continue }
                let key = item.currency ?? "USD"
                spent[key, default: 0] += price
            }

            let newStats = HomeStats(
                deckCount: decks.count,
                collectionUniques: collection.count,
                collectionCopies: collection.reduce(0) { $0 + $1.quantity },
                orderCount: orders.count,
                pendingOrders: pendingOrders,
                spentByCurrency: spent
            )

            await MainActor.run {
                self.stats = newStats
                self.recentDecks = decks
                self.isLoadingStats = false
            }
        }.value
    }
}
