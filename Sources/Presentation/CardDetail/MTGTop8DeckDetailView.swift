import SwiftUI

// MARK: - Resolved entry

/// One row in the rendered deck list. Carries the resolved `Card`
/// alongside the desired quantity and which board (mainboard /
/// sideboard) it belongs to.
private struct ResolvedDeckEntry: Identifiable {
    let id = UUID()
    let quantity: Int
    let card: Card
    let isSideboard: Bool

    /// Crude category bucket — used to group cards in the list view
    /// the same way `DeckDetailView` does. Reads the typeline.
    var category: CardCategory {
        let line = card.typeLine.lowercased()
        if line.contains("creature") { return .creature }
        if line.contains("planeswalker") { return .planeswalker }
        if line.contains("instant") { return .instant }
        if line.contains("sorcery") { return .sorcery }
        if line.contains("artifact") { return .artifact }
        if line.contains("enchantment") { return .enchantment }
        if line.contains("land") { return .land }
        return .other
    }

    enum CardCategory: String, CaseIterable {
        case creature = "Creatures"
        case planeswalker = "Planeswalkers"
        case instant = "Instants"
        case sorcery = "Sorceries"
        case artifact = "Artifacts"
        case enchantment = "Enchantments"
        case land = "Lands"
        case other = "Other"

        /// Display order on the list view.
        var sortOrder: Int {
            switch self {
            case .creature: return 0
            case .planeswalker: return 1
            case .instant: return 2
            case .sorcery: return 3
            case .artifact: return 4
            case .enchantment: return 5
            case .land: return 6
            case .other: return 7
            }
        }
    }
}

// MARK: - View mode

private enum DeckViewMode: String, CaseIterable, Identifiable {
    case list = "List"
    case grid = "Grid"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

// MARK: - View

/// Read-only deck detail for decks fetched from MTGTop8.
///
/// Mirrors the most useful parts of `DeckDetailView` (the saved-deck
/// screen) so browsing tournament decks feels the same as inspecting
/// your own:
///
/// - **List / Grid toggle** in the toolbar
/// - **Printing strategy** picker — flip every card between First Print
///   (oldest art) and Cheapest (lowest USD price) in one tap
/// - **Tappable card rows** — opens `CardDetailView` for any card
/// - **Sample Hand** button — opens `SampleHandView` populated with the
///   currently-resolved printings (mulligan, draw, reset)
/// - **Copy decklist** + **View on MTGTop8** for sharing
struct MTGTop8DeckDetailView: View {

    // MARK: - Inputs

    let deckID: String
    let deckName: String
    let player: String
    let format: String?

    private let service: MTGTop8ServiceProtocol
    private let cardRepository: CardRepositoryProtocol
    private let deckRepository: DeckListRepository

    // MARK: - State

    @State private var decklist: MTGTop8Decklist?
    @State private var resolvedMain: [ResolvedDeckEntry] = []
    @State private var resolvedSide: [ResolvedDeckEntry] = []
    @State private var isLoading: Bool = true
    @State private var isReresolving: Bool = false
    @State private var error: String?
    @State private var unresolvedNames: [String] = []
    @State private var viewMode: DeckViewMode = .list
    @State private var strategy: PrintingStrategy
    @State private var createdDeck: DeckList?

    /// Resolution cache: name → strategy → resolved card. Switching
    /// strategies twice doesn't re-hit the DB.
    @State private var cache: [String: [PrintingStrategy: Card]] = [:]

    // MARK: - Init

    init(
        deckID: String,
        deckName: String,
        player: String,
        format: String? = nil,
        cardRepository: CardRepositoryProtocol,
        deckRepository: DeckListRepository,
        service: MTGTop8ServiceProtocol = MTGTop8Service()
    ) {
        self.deckID = deckID
        self.deckName = deckName
        self.player = player
        self.format = format
        self.cardRepository = cardRepository
        self.deckRepository = deckRepository
        self.service = service
        // Default strategy is whatever the user picked in Settings.
        // The toolbar lets them override transiently per deck.
        self._strategy = State(initialValue: PrintingStrategyPreference.shared.strategy)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let deck = createdDeck {
                DeckDetailView(
                    deck: deck,
                    repository: deckRepository,
                    cardRepository: cardRepository
                )
            } else if isLoading {
                loadingState
            } else if let error {
                errorState(error)
            } else {
                content
            }
        }
        .navigationTitle(createdDeck != nil ? "" : deckName)
        .navigationBarTitleDisplayMode(.inline)
        .background(MD3Theme.background)
        .toolbar {
            if createdDeck == nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    viewModeMenu
                    strategyMenu
                    NavigationLink {
                        SampleHandView(
                            deckName: deckName,
                            cards: handCards
                        )
                    } label: {
                        Image(systemName: "play.rectangle")
                    }
                    .disabled(resolvedMain.isEmpty)
                    Menu {
                        Button {
                            Task { await createDeck() }
                        } label: {
                            Label("Create Deck", systemImage: "square.stack.3d.up")
                        }
                        .disabled(resolvedMain.isEmpty)
                        Button {
                            copyDecklist()
                        } label: {
                            Label("Copy Decklist", systemImage: "doc.on.doc")
                        }
                        Button {
                            openOnMTGTop8()
                        } label: {
                            Label("View on MTGTop8", systemImage: "safari")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await loadAndResolve()
        }
    }

    // MARK: - Toolbar menus

    private var viewModeMenu: some View {
        Menu {
            ForEach(DeckViewMode.allCases) { mode in
                Button {
                    viewMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                }
            }
        } label: {
            Image(systemName: viewMode.icon)
        }
    }

    private var strategyMenu: some View {
        Menu {
            ForEach(PrintingStrategy.allCases) { option in
                Button {
                    Task { await applyStrategy(option) }
                } label: {
                    Label(option.displayName, systemImage: option.iconName)
                }
            }
        } label: {
            Image(systemName: strategy.iconName)
        }
        .disabled(isReresolving)
    }

    // MARK: - Loading / error states

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading deck…")
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(MD3Theme.error)
            Text(message)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .list:
            listView
        case .grid:
            gridView
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if !player.isEmpty {
                    Text(player)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.primary)
                }
                Spacer()
                if isReresolving {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Text("\(totalMain) cards")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            HStack(spacing: 6) {
                Image(systemName: strategy.iconName)
                    .font(.caption2)
                Text(strategy.displayName)
                    .font(.caption2)
            }
            .foregroundStyle(MD3Theme.onSurfaceVariant)
            if !unresolvedNames.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(unresolvedNames, id: \.self) { name in
                            Text("• \(name)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("\(unresolvedNames.count) card\(unresolvedNames.count == 1 ? "" : "s") couldn't be resolved")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .tint(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - List view

    private var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if !resolvedMain.isEmpty {
                    DeckGuideView(
                        deckName: deckName,
                        format: format,
                        mainboard: resolvedMain.map { ($0.card.name, $0.quantity) },
                        sideboard: resolvedSide.map { ($0.card.name, $0.quantity) },
                        source: "MTGTop8 tournament deck by \(player)",
                        cardRepository: cardRepository,
                        deckItemPrintings: Dictionary(
                            (resolvedMain + resolvedSide).map { ($0.card.name.lowercased(), (set: $0.card.set.code, collector: $0.card.collectorNumber)) },
                            uniquingKeysWith: { first, _ in first }
                        )
                    )
                    .padding(.horizontal, 16)
                }

                ForEach(categorizedSections(resolvedMain), id: \.category) { section in
                    listSection(title: section.category.rawValue, entries: section.entries)
                }

                if !resolvedSide.isEmpty {
                    listSection(title: "Sideboard", entries: resolvedSide)
                }

                Color.clear.frame(height: 32)
            }
        }
    }

    private func listSection(title: String, entries: [ResolvedDeckEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                    NavigationLink {
                        CardDetailView(
                            card: entry.card,
                            repository: cardRepository,
                            deckRepository: deckRepository,
                            onScanAnother: {}
                        )
                    } label: {
                        listRow(entry)
                    }
                    .buttonStyle(.plain)
                    if idx < entries.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    private func listRow(_ entry: ResolvedDeckEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.quantity)×")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(MD3Theme.primary)
                .frame(width: 32, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.card.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)
                    if let manaCost = entry.card.manaCost, !manaCost.isEmpty {
                        ManaCostView(cost: manaCost, size: 12)
                    }
                }
                HStack(spacing: 4) {
                    Text(entry.card.setNameWithYear)
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .lineLimit(1)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                    Text("#\(entry.card.collectorNumber)")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                    if let usd = entry.card.prices.usd {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        Text("$\(usd)")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
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

    // MARK: - Grid view

    private var gridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                ForEach(categorizedSections(resolvedMain), id: \.category) { section in
                    gridSection(title: section.category.rawValue, entries: section.entries)
                }

                if !resolvedSide.isEmpty {
                    gridSection(title: "Sideboard", entries: resolvedSide)
                }

                Color.clear.frame(height: 32)
            }
        }
    }

    private func gridSection(title: String, entries: [ResolvedDeckEntry]) -> some View {
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

    private func gridCard(_ entry: ResolvedDeckEntry) -> some View {
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
                    if let url = imageURL(for: entry.card) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
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
            .overlay(
                Text(name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    private func imageURL(for card: Card) -> URL? {
        let str = card.imageURIs["normal"]
            ?? card.imageURIs["small"]
            ?? card.imageURIs["large"]
        return str.flatMap(URL.init(string:))
    }

    // MARK: - Categorization

    private struct Section {
        let category: ResolvedDeckEntry.CardCategory
        let entries: [ResolvedDeckEntry]
    }

    private func categorizedSections(_ entries: [ResolvedDeckEntry]) -> [Section] {
        let grouped = Dictionary(grouping: entries) { $0.category }
        return grouped
            .map { Section(category: $0.key, entries: $0.value.sorted { $0.card.name < $1.card.name }) }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }

    private var totalMain: Int {
        resolvedMain.reduce(0) { $0 + $1.quantity }
    }

    /// Flattened list of every card to feed `SampleHandView` — each
    /// resolved card is repeated by its quantity so the simulated
    /// library has the right composition.
    private var handCards: [Card] {
        resolvedMain.flatMap { entry in
            Array(repeating: entry.card, count: entry.quantity)
        }
    }

    // MARK: - Loading + resolution

    private func loadAndResolve() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await service.fetchDecklist(deckID: deckID)
            decklist = fetched
            await resolveAll(strategy: strategy)
        } catch {
            self.error = "Could not load deck"
        }
    }

    /// Resolves every entry in the current decklist using the given
    /// strategy. Cached per (name, strategy) so flipping back to a
    /// previously-seen strategy is instant.
    private func resolveAll(strategy: PrintingStrategy) async {
        guard let decklist else { return }
        isReresolving = true
        defer { isReresolving = false }

        async let main = resolve(decklist.mainboard, strategy: strategy)
        async let side = resolve(decklist.sideboard, strategy: strategy)
        let mainResult = await main
        let sideResult = await side

        resolvedMain = mainResult.entries.map { ResolvedDeckEntry(quantity: $0.quantity, card: $0.card, isSideboard: false) }
        resolvedSide = sideResult.entries.map { ResolvedDeckEntry(quantity: $0.quantity, card: $0.card, isSideboard: true) }
        unresolvedNames = mainResult.unresolved + sideResult.unresolved
    }

    private struct ResolveResult {
        let entries: [(quantity: Int, card: Card)]
        let unresolved: [String]
    }

    private func resolve(_ deckEntries: [MTGTop8DecklistEntry], strategy: PrintingStrategy) async -> ResolveResult {
        var resolved: [(quantity: Int, card: Card)] = []
        var unresolved: [String] = []
        for entry in deckEntries {
            if let card = await resolveOne(name: entry.cardName, strategy: strategy) {
                resolved.append((entry.quantity, card))
            } else {
                unresolved.append(entry.cardName)
            }
        }
        return ResolveResult(entries: resolved, unresolved: unresolved)
    }

    /// Resolves one card name to a printing matching the strategy.
    ///
    /// Lookup order (each step is hit only if the previous returned no
    /// results):
    /// 1. **Exact match** via `findAllPrintings(name:)` — handles the
    ///    common case.
    /// 2. **DFC / split / adventure fallback**: `searchCards(query:)`
    ///    + filter to records whose name starts with `<query> // `.
    ///    Catches cards like "Delver of Secrets" which Scryfall stores
    ///    as "Delver of Secrets // Insectile Aberration", or split
    ///    cards listed by half-name.
    /// 3. **Reverse-direction fallback**: when MTGTop8 lists the FULL
    ///    DFC name ("Delver of Secrets // Insectile Aberration") and
    ///    the local DB happens to have only the front-face name, try
    ///    matching by everything before the " // ".
    ///
    /// Per-(name, strategy) cached so retries and strategy flips are
    /// instant.
    private func resolveOne(name: String, strategy: PrintingStrategy) async -> Card? {
        if let cached = cache[name]?[strategy] {
            return cached
        }

        let printings = await lookupPrintings(forName: name)
        guard !printings.isEmpty else { return nil }

        let chosen = strategy.pick(from: printings)
        cache[name, default: [:]][strategy] = chosen
        return chosen
    }

    /// Performs the multi-step lookup described in `resolveOne`. Each
    /// fallback is only tried if the previous step came back empty,
    /// so the common path (exact match) stays a single DB query.
    private func lookupPrintings(forName name: String) async -> [Card] {
        // 1. Exact match
        if let exact = try? await cardRepository.findAllPrintings(name: name),
           !exact.isEmpty {
            return exact
        }

        // 2. DFC/split/adventure: source listed only the front face,
        // local DB has the full "Front // Back" name.
        if let candidates = try? await cardRepository.searchCards(query: name) {
            let prefix = "\(name.lowercased()) // "
            let frontFaceMatches = candidates.filter { card in
                card.name.lowercased().hasPrefix(prefix)
            }
            if !frontFaceMatches.isEmpty {
                // Multiple back-faces would all map to the same set of
                // front-face printings; dedupe by scryfallID just in
                // case the substring search returned overlapping rows.
                var seen = Set<String>()
                return frontFaceMatches.filter { card in
                    seen.insert(card.scryfallID).inserted
                }
            }
        }

        // 3. Reverse: source has "Front // Back" but local DB stores
        // only the front face by itself.
        if name.contains(" // ") {
            let frontFace = name.components(separatedBy: " // ").first ?? name
            if frontFace != name,
               let printings = try? await cardRepository.findAllPrintings(name: frontFace),
               !printings.isEmpty {
                return printings
            }
        }

        return []
    }

    private func applyStrategy(_ newStrategy: PrintingStrategy) async {
        guard newStrategy != strategy else { return }
        strategy = newStrategy
        await resolveAll(strategy: newStrategy)
    }

    // MARK: - Actions

    private func createDeck() async {
        guard createdDeck == nil else { return }
        guard let deck = try? deckRepository.createDeck(
            name: deckName,
            format: format
        ) else { return }

        deck.referenceURL = "https://mtgtop8.com/event?d=\(deckID)"

        // Mainboard — resolved cards
        for entry in resolvedMain {
            if let item = try? deckRepository.addItem(
                card: entry.card, quantity: entry.quantity, to: deck, zone: "mainboard"
            ) {
                item.statusRaw = "needed"
            }
        }

        // Sideboard — resolved cards
        for entry in resolvedSide {
            if let item = try? deckRepository.addItem(
                card: entry.card, quantity: entry.quantity, to: deck, zone: "sideboard"
            ) {
                item.statusRaw = "needed"
            }
        }

        // Unresolved cards — add by name so nothing is lost
        if let decklist {
            let resolvedMainNames = Set(resolvedMain.map { $0.card.name.lowercased() })
            let resolvedSideNames = Set(resolvedSide.map { $0.card.name.lowercased() })
            for entry in decklist.mainboard where !resolvedMainNames.contains(entry.cardName.lowercased()) {
                _ = try? deckRepository.addItemByName(
                    cardName: entry.cardName, quantity: entry.quantity,
                    status: .needed, zone: "mainboard", to: deck
                )
            }
            for entry in decklist.sideboard where !resolvedSideNames.contains(entry.cardName.lowercased()) {
                _ = try? deckRepository.addItemByName(
                    cardName: entry.cardName, quantity: entry.quantity,
                    status: .needed, zone: "sideboard", to: deck
                )
            }
        }

        createdDeck = deck
    }

    private func copyDecklist() {
        guard let decklist else { return }
        var lines: [String] = []
        for entry in decklist.mainboard {
            lines.append("\(entry.quantity) \(entry.cardName)")
        }
        if !decklist.sideboard.isEmpty {
            lines.append("")
            lines.append("Sideboard")
            for entry in decklist.sideboard {
                lines.append("\(entry.quantity) \(entry.cardName)")
            }
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    private func openOnMTGTop8() {
        guard let url = URL(string: "https://mtgtop8.com/event?d=\(deckID)") else { return }
        UIApplication.shared.open(url)
    }
}
