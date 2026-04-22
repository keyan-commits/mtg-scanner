import SwiftUI

/// Shows the full mainboard of a `ClassicArchetype`, with each card resolved
/// to a specific printing via the local Scryfall DB. Prefers the *oldest*
/// printing where possible so the cards look era-appropriate (e.g. 1995
/// Hypnotic Specter from 4ED, not a modern reprint). Lets the user save
/// the entire decklist as their own deck in one tap.
struct ClassicDeckDetailView: View {

    let archetype: ClassicArchetype
    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol

    /// Resolved mainboard cards in display order. Each entry maps a
    /// canonical name + quantity to the actual `Card` we found in the DB.
    @State private var resolved: [ResolvedEntry] = []
    /// Resolved sideboard cards (15 max). Empty when the archetype has no
    /// curated sideboard.
    @State private var resolvedSideboard: [ResolvedEntry] = []
    @State private var unresolved: [String] = []
    @State private var isLoading: Bool = true
    @State private var savedDeckID: UUID?
    @State private var saveError: String?
    @State private var viewMode: ViewMode = .list
    @State private var ownedQuantities: [String: Int] = [:]
    @Bindable private var currencyService = CurrencyService.shared

    private enum ViewMode: String, CaseIterable, Hashable {
        case list
        case grid
        var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    @Environment(\.dismiss) private var dismiss

    struct ResolvedEntry: Identifiable, Sendable {
        let id = UUID()
        let card: Card
        let quantity: Int
    }

    /// Process-wide cache of resolved decks keyed by `archetype.id`.
    /// Survives view recreation so navigating list → card detail →
    /// back to list doesn't re-trigger the "Resolving cards…" load
    /// state. Cards are looked up against the local Scryfall DB
    /// (which is also persistent), so the data is stable for the
    /// life of the app process.
    nonisolated(unsafe) private static var resolvedCache: [String: ResolvedDeck] = [:]
    nonisolated(unsafe) private static let resolvedCacheLock = NSLock()

    private struct ResolvedDeck: Sendable {
        let mainboard: [ResolvedEntry]
        let sideboard: [ResolvedEntry]
        let missing: [String]
    }

    private static func cachedDeck(for archetypeID: String) -> ResolvedDeck? {
        resolvedCacheLock.lock()
        defer { resolvedCacheLock.unlock() }
        return resolvedCache[archetypeID]
    }

    private static func storeDeck(_ deck: ResolvedDeck, for archetypeID: String) {
        resolvedCacheLock.lock()
        defer { resolvedCacheLock.unlock() }
        resolvedCache[archetypeID] = deck
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
        .navigationTitle(archetype.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    SampleHandView(
                        deckName: archetype.name,
                        cards: handCards
                    )
                } label: {
                    Image(systemName: "play.rectangle")
                }
                .disabled(resolved.isEmpty)
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
        }
        .task {
            ownedQuantities = (try? deckRepository.ownedQuantitiesByName()) ?? [:]
            await resolveCards()
        }
    }

    /// Flattens the resolved mainboard into a single `[Card]` array,
    /// repeating each card by its quantity. Feeds `SampleHandView`'s
    /// `init(deckName:cards:)` so the simulated library has the
    /// correct composition for opening-hand math.
    private var handCards: [Card] {
        resolved.flatMap { entry in
            Array(repeating: entry.card, count: entry.quantity)
        }
    }

    // MARK: - List body

    private var listBody: some View {
        List {
            Section {
                headerCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if !ownedQuantities.isEmpty {
                Section {
                    collectionSummary
                }
            }

            if archetype.cardTypes != nil && resolved.isEmpty {
                // Hardcoded path: render instantly from hardcoded data
                hardcodedCardSections
            } else if !resolved.isEmpty {
                cardSections
                if !resolvedSideboard.isEmpty {
                    sideboardSection
                }
            } else if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading cards…")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                }
            }
            if !unresolved.isEmpty && !isLoading {
                Section {
                    ForEach(unresolved, id: \.self) { name in
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.gray)
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                    }
                } header: {
                    Text("Not in local database")
                } footer: {
                    Text("These cards are part of the canonical list but couldn't be found in the local Scryfall DB. They'll be skipped if you save the deck.")
                        .font(.caption2)
                }
            }
            Section {
                saveButton
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Grid body

    private var gridBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                headerCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if !ownedQuantities.isEmpty {
                    collectionSummary
                        .padding(.horizontal, 16)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Resolving cards…")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else {
                    ForEach(groupedByCategory(resolved), id: \.category) { entry in
                        gridSection(title: entry.category.rawValue, entries: entry.entries)
                    }
                    if !resolvedSideboard.isEmpty {
                        gridSection(title: "Sideboard", entries: resolvedSideboard)
                    }
                    if !unresolved.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Not in local database (\(unresolved.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                                .padding(.horizontal, 16)
                            ForEach(unresolved, id: \.self) { name in
                                Text("• \(name)")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                                    .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 8)
                    }
                    saveButton
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                Color.clear.frame(height: 24)
            }
        }
        .background(MD3Theme.background)
    }

    private func gridSection(title: String, entries: [ResolvedEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Text("(\(entries.reduce(0) { $0 + $1.quantity }))")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(entries) { entry in
                        gridCard(entry)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func gridCard(_ entry: ResolvedEntry) -> some View {
        NavigationLink {
            CardDetailView(
                card: entry.card,
                repository: cardRepository,
                deckRepository: deckRepository,
                onScanAnother: {}
            )
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if let urlString = entry.card.imageURIs["normal"]
                        ?? entry.card.imageURIs["small"]
                        ?? entry.card.imageURIs["large"],
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                gridPlaceholder(entry.card.name)
                            }
                        }
                    } else {
                        gridPlaceholder(entry.card.name)
                    }
                    Text("\(entry.quantity)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(6)
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

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(archetype.format)
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.onSecondaryContainer)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(MD3Theme.secondaryContainer)
                    .clipShape(Capsule())
                Text(archetype.era)
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Spacer()
                Text("\(archetype.totalCards) cards")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            Text(archetype.description)
                .font(.callout)
                .foregroundStyle(MD3Theme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Text("Source: \(archetype.source)")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    // MARK: - Collection summary

    private var collectionSummary: some View {
        let totalNeeded = archetype.mainboard.values.reduce(0, +)
        let totalOwned = archetype.mainboard.reduce(0) { sum, entry in
            sum + min(entry.value, ownedQuantities[entry.key] ?? 0)
        }
        let percentage = totalNeeded > 0 ? Double(totalOwned) / Double(totalNeeded) * 100 : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(MD3Theme.primary)
                Text("You own \(totalOwned)/\(totalNeeded) mainboard cards (\(Int(round(percentage)))%)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
            }
            ProgressView(value: percentage, total: 100)
                .tint(percentage >= 70 ? .green : percentage >= 40 ? .orange : .gray)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Card sections

    /// Renders the full categorized deck layout entirely from hardcoded data.
    /// Zero DB queries — card types, mana costs, set codes all come from
    /// the ClassicArchetype's hardcoded dictionaries. Images load per-row
    /// in the background once resolution completes.
    @ViewBuilder
    private var hardcodedCardSections: some View {
        let types = archetype.cardTypes ?? [:]
        let costs = archetype.cardManaCosts ?? [:]
        let sets = archetype.cardSets ?? [:]

        let allCards = archetype.mainboard
            .map { (name: $0.key, qty: $0.value, type: types[$0.key] ?? "Other", cost: costs[$0.key], set: sets[$0.key]) }

        let categories = ["Creature", "Instant", "Sorcery", "Enchantment", "Artifact", "Land", "Other"]
        ForEach(categories, id: \.self) { category in
            let cards = allCards.filter { $0.type == category }.sorted { $0.name < $1.name }
            if !cards.isEmpty {
                Section {
                    ForEach(cards, id: \.name) { card in
                        HStack(spacing: 12) {
                            Text("\(card.qty)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(MD3Theme.primary)
                                .frame(width: 24, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(card.name)
                                        .font(MD3Typography.bodyMedium)
                                        .foregroundStyle(MD3Theme.onSurface)
                                    if let cost = card.cost, !cost.isEmpty {
                                        Text(cost)
                                            .font(.caption2)
                                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                                    }
                                }
                                if let setCode = card.set {
                                    Text(setCode.uppercased())
                                        .font(.caption2)
                                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    HStack {
                        Text(category == "Creature" ? "CREATURES" :
                             category == "Instant" ? "INSTANTS" :
                             category == "Sorcery" ? "SORCERIES" :
                             category == "Enchantment" ? "ENCHANTMENTS" :
                             category == "Artifact" ? "ARTIFACTS" :
                             category == "Land" ? "LANDS" : category.uppercased())
                        Spacer()
                        Text("\(cards.reduce(0) { $0 + $1.qty })")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }

        if let sb = archetype.sideboard {
            let sbCards = sb.map { (name: $0.key, qty: $0.value, set: sets[$0.key]) }.sorted { $0.name < $1.name }
            Section {
                ForEach(sbCards, id: \.name) { card in
                    HStack(spacing: 12) {
                        Text("\(card.qty)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(MD3Theme.secondary)
                            .frame(width: 24, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.name)
                                .font(MD3Typography.bodyMedium)
                                .foregroundStyle(MD3Theme.onSurface)
                            if let setCode = card.set {
                                Text(setCode.uppercased())
                                    .font(.caption2)
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("SIDEBOARD")
                    Spacer()
                    Text("\(archetype.sideboardCount)")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    /// Shows card names, quantities, and set codes instantly from
    /// hardcoded data. No loading indicators — images appear when resolved.
    @ViewBuilder
    private var unresolvedCardSections: some View {
        let sets = archetype.cardSets ?? [:]
        let sorted = archetype.mainboard
            .map { (name: $0.key, qty: $0.value, set: sets[$0.key]) }
            .sorted { $0.name < $1.name }
        Section {
            ForEach(sorted, id: \.name) { entry in
                HStack(spacing: 12) {
                    Text("\(entry.qty)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(MD3Theme.primary)
                        .frame(width: 24, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(MD3Typography.bodyMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                        if let setCode = entry.set {
                            Text(setCode.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        } header: {
            HStack {
                Text("MAINBOARD")
                Spacer()
                Text("\(archetype.totalCards)")
                    .font(.caption.weight(.semibold))
            }
        }
        if let sb = archetype.sideboard {
            let sortedSB = sb.map { (name: $0.key, qty: $0.value, set: sets[$0.key]) }.sorted { $0.name < $1.name }
            Section {
                ForEach(sortedSB, id: \.name) { entry in
                    HStack(spacing: 12) {
                        Text("\(entry.qty)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(MD3Theme.secondary)
                            .frame(width: 24, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(MD3Typography.bodyMedium)
                                .foregroundStyle(MD3Theme.onSurface)
                            if let setCode = entry.set {
                                Text(setCode.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("SIDEBOARD")
                    Spacer()
                    Text("\(archetype.sideboardCount)")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var cardSections: some View {
        let groups = groupedByCategory(resolved)
        ForEach(groups, id: \.category) { entry in
            Section {
                ForEach(entry.entries) { item in
                    NavigationLink {
                        CardDetailView(
                            card: item.card,
                            repository: cardRepository,
                            deckRepository: deckRepository,
                            onScanAnother: {}
                        )
                    } label: {
                        cardRow(item)
                    }
                }
            } header: {
                HStack {
                    Text(entry.category.rawValue.uppercased())
                    Spacer()
                    Text("\(entry.entries.reduce(0) { $0 + $1.quantity })")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private func cardRow(_ item: ResolvedEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(item.quantity)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .frame(minWidth: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.card.name)
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)
                    if let manaCost = item.card.manaCost, !manaCost.isEmpty {
                        ManaCostView(cost: manaCost, size: 13)
                    }
                }
                Text("\(item.card.setNameWithYear) · #\(item.card.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            if let usdString = item.card.prices.usd, let usd = Double(usdString) {
                let preferred = LocalCurrency.current
                let display: String = {
                    if let converted = currencyService.convert(usd, to: preferred) {
                        return LocalCurrency.format(converted, currency: preferred)
                    }
                    return "$\(MoneyFormat.compact(usd))"
                }()
                Text(display)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.primary)
                    .monospacedDigit()
            }
            let owned = ownedQuantities[item.card.name] ?? 0
            if owned >= item.quantity {
                Text("✓ \(owned)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            } else if owned > 0 {
                Text("\(owned)/\(item.quantity)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var sideboardSection: some View {
        Section {
            ForEach(resolvedSideboard) { item in
                NavigationLink {
                    CardDetailView(
                        card: item.card,
                        repository: cardRepository,
                        deckRepository: deckRepository,
                        onScanAnother: {}
                    )
                } label: {
                    cardRow(item)
                }
            }
        } header: {
            HStack {
                Text("SIDEBOARD")
                Spacer()
                Text("\(resolvedSideboard.reduce(0) { $0 + $1.quantity })")
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private struct CategoryEntry {
        let category: CardCategory
        let entries: [ResolvedEntry]
    }

    private func groupedByCategory(_ entries: [ResolvedEntry]) -> [CategoryEntry] {
        let byCategory = Dictionary(grouping: entries) { entry in
            CardCategory.from(typeLine: entry.card.typeLine)
        }
        return byCategory
            .map { CategoryEntry(category: $0.key, entries: $0.value.sorted { $0.card.name < $1.card.name }) }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }

    // MARK: - Save button

    @ViewBuilder
    private var saveButton: some View {
        if savedDeckID != nil {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Saved as a new deck")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MD3Theme.onSurface)
                    Spacer()
                }
                if !resolvedSideboard.isEmpty {
                    Text("Sideboard cards were not included (decks don't track sideboards yet).")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let saveError {
            VStack(alignment: .leading, spacing: 6) {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                MD3FilledButton("Try Again") { saveAsNewDeck() }
            }
        } else {
            MD3FilledButton("Save as new deck") { saveAsNewDeck() }
        }
    }

    // MARK: - Resolve

    /// Looks each canonical card up in the local Scryfall DB. Picks the
    /// *oldest* printing where multiple are available so the resulting
    /// deck looks era-appropriate.
    ///
    /// Result is cached process-wide via `Self.resolvedCache` so the
    /// "Resolving cards…" load state only fires the first time the
    /// user opens an archetype. Subsequent visits — including
    /// returning from a `CardDetailView` push — populate from the
    /// cache instantly without re-running the lookup loop. SwiftUI
    /// cancels the original `.task` when the view disappears, which
    /// is why an uncached re-entry would otherwise re-show the
    /// spinner from scratch.
    private func resolveCards() async {
        // Cache hit: skip the entire load + spinner.
        if let cached = Self.cachedDeck(for: archetype.id) {
            resolved = cached.mainboard
            resolvedSideboard = cached.sideboard
            unresolved = cached.missing
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        var resolvedList: [ResolvedEntry] = []
        var resolvedSide: [ResolvedEntry] = []
        var missing: [String] = []

        // Mainboard
        let sortedMain = archetype.mainboard
            .map { (name: $0.key, qty: $0.value) }
            .sorted { $0.name < $1.name }
        for entry in sortedMain {
            if let card = await pickPrinting(name: entry.name) {
                resolvedList.append(ResolvedEntry(card: card, quantity: entry.qty))
            } else {
                missing.append(entry.name)
            }
        }

        // Sideboard (if curated)
        if let sb = archetype.sideboard {
            let sortedSide = sb
                .map { (name: $0.key, qty: $0.value) }
                .sorted { $0.name < $1.name }
            for entry in sortedSide {
                if let card = await pickPrinting(name: entry.name) {
                    resolvedSide.append(ResolvedEntry(card: card, quantity: entry.qty))
                } else {
                    missing.append(entry.name)
                }
            }
        }

        resolved = resolvedList
        resolvedSideboard = resolvedSide
        unresolved = missing

        // Persist into the process-wide cache so re-entry is instant.
        Self.storeDeck(
            ResolvedDeck(
                mainboard: resolvedList,
                sideboard: resolvedSide,
                missing: missing
            ),
            for: archetype.id
        )
    }

    private func pickPrinting(name: String) async -> Card? {
        // Fast path: when a preferred set code is hardcoded, do a direct
        // indexed lookup by (name + setCode) instead of searching all printings.
        // Scryfall stores set codes as lowercase, so lowercase before querying.
        if let preferredSet = archetype.cardSets?[name] {
            let variants = (try? await cardRepository.findVariants(name: name, setCode: preferredSet.lowercased())) ?? []
            if let match = variants.first { return match }
        }

        // Slow path fallback: search all printings by name
        guard let printings = try? await cardRepository.findAllPrintings(name: name),
              !printings.isEmpty else {
            return try? await cardRepository.identifyCard(name: name)
        }

        // InQuest decks (have cardSets): newest printing within the deck's era
        if archetype.cardSets != nil {
            let eraCutoff = "\(archetype.era)-12-31"
            let eraPrintings = printings.filter { ($0.releasedAt ?? "9999") <= eraCutoff }
            let pool = eraPrintings.isEmpty ? printings : eraPrintings
            return pool.sorted { ($0.releasedAt ?? "0000") > ($1.releasedAt ?? "0000") }.first
        }

        // Classic decks: prefer oldest printing for authenticity
        return printings.sorted { ($0.releasedAt ?? "9999") < ($1.releasedAt ?? "9999") }.first
    }

    // MARK: - Save as new deck

    private func saveAsNewDeck() {
        do {
            let deck = try deckRepository.createDeck(
                name: "\(archetype.name) (\(archetype.era))",
                format: archetype.format
            )
            for entry in resolved {
                _ = try deckRepository.addItem(
                    card: entry.card,
                    quantity: entry.quantity,
                    to: deck
                )
            }
            savedDeckID = deck.id
            saveError = nil
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
