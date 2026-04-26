import SwiftUI

/// Shows a deck's purchase checklist grouped by status.
/// Tap items to change status, swipe to delete.
struct DeckDetailView: View {

    let deck: DeckList
    let repository: DeckListRepository
    let cardRepository: CardRepositoryProtocol?
    let autoOpenImport: Bool

    @State private var items: [PurchaseItem] = []
    @State private var markOrderedItem: PurchaseItem?
    @State private var showImportSheet: Bool = false
    @State private var showImportSideboardSheet: Bool = false
    @State private var showAddCardSheet: Bool = false
    @State private var showBulkOrderSheet: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var changePrintingItem: PurchaseItem?
    @State private var viewingCard: Card?
    @State private var loadingCardItemID: UUID?
    @State private var showEditSheet: Bool = false
    @State private var editName: String = ""
    @State private var editFormat: DeckFormat = .freeform
    /// Cached per-card legality status keyed by "setCode|collectorNumber".
    /// Only populated when the deck format is non-freeform.
    @State private var legalityCache: [String: LegalityStatus] = [:]
    /// Total spent on this deck, grouped by currency. Re-fetched on each reload.
    @State private var spentByCurrency: [String: Double] = [:]
    /// Owned-from-collection counter: how many of this deck's items are
    /// already physically owned. `ownedCount/totalCards`.
    @State private var ownedCount: Int = 0
    /// Suggested cards when the deck is undersized for its format.
    @State private var suggestionResult: DeckSuggestionResult = .empty
    @State private var loadingSuggestions: Bool = false
    /// View mode toggle: list (rich, status-aware rows) vs grid (visual,
    /// horizontal scrollers of card images). Persisted across the view's
    /// lifetime only — defaults to list on each appear.
    @State private var viewMode: DeckViewMode = .list
    /// Resolved cards keyed by scryfallID for the grid view's image lookups.
    /// Lazy-loaded the first time the user switches to grid mode.
    @State private var resolvedCards: [String: Card] = [:]
    @State private var loadingGridCards: Bool = false
    /// True while the "Change All Printings" operation is running.
    @State private var changingAllPrintings: Bool = false
    /// Controls the printing strategy picker confirmation dialog.
    @State private var showPrintingStrategyPicker: Bool = false
    /// Number of cards whose sideboard was auto-suggested (for the toast).
    @State private var sideboardSuggestCount: Int = 0
    @State private var showSideboardSuggestToast: Bool = false
    @State private var showSideboardPicker: Bool = false
    @State private var sideboardCandidates: [(name: String, items: [PurchaseItem], moveCount: Int)] = []
    @State private var showSideboardGuide: Bool = false
    @State private var isFixingDeck: Bool = false
    @State private var fixDeckError: String?

    enum DeckViewMode: String, CaseIterable, Identifiable {
        case list = "List"
        case grid = "Grid"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid: return "rectangle.grid.2x2"
            }
        }
    }

    private let suggestionService = DeckSuggestionService(mtgTop8Service: MTGTop8Service())

    private var suggestions: [DeckSuggestion] { suggestionResult.suggestions }

    private var deckFormat: DeckFormat {
        DeckFormat.from(stored: deck.format)
    }

    init(deck: DeckList, repository: DeckListRepository, cardRepository: CardRepositoryProtocol? = nil, autoOpenImport: Bool = false) {
        self.deck = deck
        self.repository = repository
        self.cardRepository = cardRepository
        self.autoOpenImport = autoOpenImport
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                if viewMode == .list {
                    listView
                } else {
                    gridView
                }
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Picker("View", selection: $viewMode) {
                        ForEach(DeckViewMode.allCases) { mode in
                            Image(systemName: mode.icon).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                    .onChange(of: viewMode) { _, newValue in
                        if newValue == .grid {
                            Task { await loadGridCardsIfNeeded() }
                        }
                    }
                    ScreenHelpButton(title: "Deck Detail", sections: [
                        HelpSection(icon: "checkmark.seal", title: "Status lifecycle",
                                    body: "Each card copy moves through Needed → Ordered → Arrived. The compact header shows the totals at a glance and the progress bar shows how many you've collected."),
                        HelpSection(icon: "exclamationmark.triangle", title: "Legality banner",
                                    body: "If your deck is in a non-Freeform format and contains banned/restricted cards, an orange banner lists them. Tap the pencil button to switch to Freeform if it's the wrong format."),
                        HelpSection(icon: "exclamationmark.circle", title: "Deck size warning",
                                    body: "If your deck is below the format minimum (60 for most, 100 for Commander), a yellow banner shows. Suggested cards from tournament archetypes appear underneath — tap to add them in one go."),
                        HelpSection(icon: "shippingbox", title: "Toolbar actions",
                                    body: "Pencil = edit name/format. Box = view orders for this deck. Plus = add a single card. Down arrow = paste a decklist. Box+arrow = paste a seller's bulk order to mark cards ordered."),
                        HelpSection(icon: "rectangle.stack", title: "Tap a card",
                                    body: "Opens the per-copy view where you can see related orders, mark individual copies as arrived, change the printing for all copies at once, and see live prices."),
                    ])
                    Button {
                        beginEdit()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    NavigationLink {
                        OrdersScreen(
                            repository: repository,
                            deckID: deck.id,
                            titleOverride: "Orders · \(deck.name)"
                        )
                    } label: {
                        Image(systemName: "shippingbox")
                    }
                    if let cardRepository {
                        NavigationLink {
                            SampleHandView(
                                deck: deck,
                                deckRepository: repository,
                                cardRepository: cardRepository
                            )
                        } label: {
                            Image(systemName: "play.rectangle")
                        }
                    }
                    if cardRepository != nil {
                        Menu {
                            Button {
                                showImportSideboardSheet = true
                            } label: {
                                Label("Import Sideboard", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                suggestSideboard()
                            } label: {
                                Label("Suggest Sideboard", systemImage: "arrow.right.square")
                            }
                            .disabled(items.isEmpty)

                            Button {
                                showSideboardGuide = true
                            } label: {
                                Label("Sideboard Guide", systemImage: "book.pages")
                            }

                            Button {
                                showPrintingStrategyPicker = true
                            } label: {
                                Label("Change All Printings", systemImage: "rectangle.stack")
                            }
                            .disabled(items.isEmpty || changingAllPrintings)

                            let mainCount = items.filter { $0.zone == "mainboard" }.count
                            if mainCount > 60 {
                                Button {
                                    Task { await aiFixDeck() }
                                } label: {
                                    Label("AI Fix Deck (60+15)", systemImage: "sparkles")
                                }
                                .disabled(isFixingDeck)
                            }

                            Divider()

                            Button {
                                showClearConfirmation = true
                            } label: {
                                Label("Reset Collected Status", systemImage: "arrow.counterclockwise")
                            }
                            .disabled(items.filter { $0.status != .needed }.isEmpty)
                        } label: {
                            if changingAllPrintings || isFixingDeck {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                        }
                        Button {
                            showAddCardSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        Button {
                            showImportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Button {
                            showBulkOrderSheet = true
                        } label: {
                            Image(systemName: "shippingbox.and.arrow.backward")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            editSheet
        }
        .sheet(item: $markOrderedItem) { item in
            MarkOrderedSheet(item: item, repository: repository) {
                reload()
                markOrderedItem = nil
            }
        }
        .sheet(isPresented: $showImportSheet) {
            if let cardRepository {
                ImportDecklistSheet(
                    deck: deck,
                    deckRepository: repository,
                    cardRepository: cardRepository,
                    onDone: { reload() }
                )
            }
        }
        .sheet(isPresented: $showImportSideboardSheet) {
            if let cardRepository {
                ImportDecklistSheet(
                    deck: deck,
                    deckRepository: repository,
                    cardRepository: cardRepository,
                    defaultZone: "sideboard",
                    onDone: { reload() }
                )
            }
        }
        .sheet(isPresented: $showAddCardSheet) {
            if let cardRepository {
                AddCardToDeckSheet(
                    deck: deck,
                    deckRepository: repository,
                    cardRepository: cardRepository,
                    onAdded: { reload() }
                )
            }
        }
        .sheet(isPresented: $showBulkOrderSheet) {
            MarkOrderReceivedSheet(
                deck: deck,
                deckRepository: repository,
                onDone: { reload() }
            )
        }
        .sheet(item: $changePrintingItem) { item in
            if let cardRepository {
                ChangePrintingSheet(
                    item: item,
                    deckRepository: repository,
                    cardRepository: cardRepository,
                    onChanged: { reload() }
                )
            }
        }
        .sheet(item: $viewingCard) { card in
            NavigationStack {
                CardDetailView(card: card, repository: cardRepository, deckRepository: repository, onScanAnother: {
                    viewingCard = nil
                })
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { viewingCard = nil }
                    }
                }
            }
        }
        .confirmationDialog("Change All Printings", isPresented: $showPrintingStrategyPicker, titleVisibility: .visible) {
            ForEach(PrintingStrategy.allCases) { strategy in
                Button(strategy.displayName) {
                    Task { await changeAllPrintings(to: strategy) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pick a printing strategy to apply to every card in this deck.")
        }
        .sheet(isPresented: $showSideboardPicker) {
            sideboardPickerSheet
        }
        .sheet(isPresented: $showSideboardGuide) {
            SideboardGuideSheet(format: deckFormat, sideboardCards: items.filter { $0.zone == "sideboard" }.map { $0.cardName.lowercased() })
        }
        .confirmationDialog("Reset Collected Status", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Reset & Match Collection", role: .destructive) {
                // Step 1: Reset all to needed
                for item in items {
                    item.status = .needed
                }
                // Step 2: Match against collection
                let owned = (try? repository.ownedQuantitiesByName()) ?? [:]
                var used: [String: Int] = [:]  // track how many we've matched per card name
                for item in items {
                    let name = item.cardName
                    let totalOwned = owned[name] ?? 0
                    let alreadyUsed = used[name] ?? 0
                    if alreadyUsed < totalOwned {
                        item.status = .arrived
                        used[name] = alreadyUsed + 1
                    }
                }
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reset tracking and re-match against your collection. Cards you own will be marked as collected.")
        }
        .overlay(alignment: .bottom) {
            if showSideboardSuggestToast {
                Text(sideboardSuggestCount > 0
                     ? "Moved \(sideboardSuggestCount) card\(sideboardSuggestCount == 1 ? "" : "s") to sideboard"
                     : "No common sideboard cards detected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { showSideboardSuggestToast = false }
                        }
                    }
            }
        }
        .onAppear {
            reload()
            Task {
                await backfillManaCosts()
                if let cardRepository {
                    await repository.backfillPriceSnapshotsIfNeeded(cardRepository: cardRepository)
                }
                await refreshLegality()
                await loadSuggestions()
            }
            if autoOpenImport && cardRepository != nil {
                // Defer slightly so the navigation transition completes first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showImportSheet = true
                }
            }
        }
    }

    /// Fills in manaCost / typeLine for legacy items that were imported before those fields existed.
    /// Looks each card up in the local DB and saves the result.
    private func backfillManaCosts() async {
        guard let cardRepository else { return }
        var didUpdate = false
        for item in items where item.manaCost == nil || item.typeLine == nil {
            if let card = try? await cardRepository.fetchCard(set: item.setCode, collectorNumber: item.collectorNumber) {
                try? repository.updateMetadata(item, manaCost: card.manaCost, typeLine: card.typeLine)
                didUpdate = true
            }
        }
        if didUpdate {
            reload()
        }
    }

    // MARK: - Edit Deck

    private func beginEdit() {
        editName = deck.name
        editFormat = deckFormat
        showEditSheet = true
    }

    private func saveEdit() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let stored = editFormat == .freeform ? nil : editFormat.rawValue
        try? repository.renameDeck(deck, name: trimmed, format: stored)
        showEditSheet = false
        // Re-run legality check since the format may have changed
        Task { await refreshLegality() }
    }

    @ViewBuilder
    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Deck Info") {
                    TextField("Deck Name", text: $editName)
                    Picker("Format", selection: $editFormat) {
                        ForEach(DeckFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                }
            }
            .navigationTitle("Edit Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showEditSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveEdit() }
                        .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Deck Size & Suggestions

    @ViewBuilder
    private func deckSizeBanner(minSize: Int) -> some View {
        let mbCount = mainboardCount
        let short = minSize - mbCount
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.yellow)
                Text("\(mbCount)/\(minSize) mainboard · \(short) short of \(deckFormat.displayName) minimum")
                    .font(.subheadline.bold())
                    .foregroundStyle(MD3Theme.onSurface)
            }
            Text("Below: tournament cards you don't have yet, ranked by how often they show up in decks featuring your existing cards.")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var suggestionsList: some View {
        if loadingSuggestions {
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("Looking up tournament decks…")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, suggestion in
                    suggestionRow(suggestion)
                    if idx < suggestions.count - 1 {
                        Divider()
                    }
                }
            }
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: DeckSuggestion) -> some View {
        Button {
            Task { await addSuggestion(suggestion) }
        } label: {
            HStack(spacing: 10) {
                Text("+")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MD3Theme.primary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.cardName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MD3Theme.onSurface)
                    if let recommended = suggestion.recommendedQuantity {
                        // Archetype-based: show how many copies the canonical
                        // version recommends (which is the missing count).
                        Text("Add \(recommended)× to match canonical list")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    } else {
                        // MTGTop8-based: show frequency stats.
                        Text("In \(suggestion.frequency)/\(suggestion.totalDecksScanned) decks · avg \(String(format: "%.1f", suggestion.averageQuantity))×")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
                Spacer()
                if let recommended = suggestion.recommendedQuantity {
                    Text("\(recommended)×")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MD3Theme.primary)
                        .monospacedDigit()
                } else {
                    Text("\(suggestion.frequencyPercent)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MD3Theme.primary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadSuggestions() async {
        // Archetype matching works regardless of format (it's purely based
        // on card overlap), so we don't gate on `scryfallKey`. The minimum
        // deck size check still applies — only undersized decks need help.
        guard let minSize = deckFormat.minDeckSize, mainboardCount < minSize else {
            suggestionResult = .empty
            return
        }
        loadingSuggestions = true
        defer { loadingSuggestions = false }
        let names = items.map { $0.cardName }
        // Pass the deck's format for the MTGTop8 fallback path (unused if
        // an archetype match wins).
        let formatKey = deckFormat.scryfallKey ?? "premodern"
        suggestionResult = await suggestionService.suggestions(
            forDeckCards: names,
            format: formatKey,
            limit: 12
        )
    }

    private func addSuggestion(_ suggestion: DeckSuggestion) async {
        guard let cardRepository else { return }
        // For archetype-based suggestions, add the full recommended count
        // in one tap. For MTGTop8 suggestions, add 1 (no recommended count).
        let qty = suggestion.recommendedQuantity ?? 1
        if let card = try? await cardRepository.identifyCard(name: suggestion.cardName) {
            _ = try? repository.addItem(card: card, quantity: qty, to: deck)
            reload()
            // Re-run suggestions since the deck composition changed
            await loadSuggestions()
        }
    }

    // MARK: - Format Legality

    /// Looks up each unique printing in the deck and caches its legality
    /// for the deck's selected format. Skipped entirely for freeform decks.
    private func refreshLegality() async {
        guard let cardRepository, let formatKey = deckFormat.scryfallKey else {
            legalityCache = [:]
            return
        }
        var cache: [String: LegalityStatus] = [:]
        // Dedup by printing key — multiple copies share legality
        let uniqueKeys = Set(items.map { "\($0.setCode)|\($0.collectorNumber)" })
        for key in uniqueKeys {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if let card = try? await cardRepository.fetchCard(set: parts[0], collectorNumber: parts[1]),
               let status = card.legalities.status(for: formatKey) {
                cache[key] = status
            }
        }
        legalityCache = cache
    }

    private func legalityKey(_ item: PurchaseItem) -> String {
        "\(item.setCode)|\(item.collectorNumber)"
    }

    /// Returns true when the item is known to be non-legal in the deck format.
    /// Returns false for freeform decks or when legality is unknown.
    private func isFlagged(_ item: PurchaseItem) -> Bool {
        guard deckFormat.scryfallKey != nil else { return false }
        guard let status = legalityCache[legalityKey(item)] else { return false }
        return status != .legal
    }

    /// Card groups (one per printing) that are flagged for the current format.
    private var illegalGroups: [(group: CardGroup, status: LegalityStatus)] {
        guard deckFormat.scryfallKey != nil else { return [] }
        return groupedCards.compactMap { group in
            guard let status = legalityCache[legalityKey(group.representative)],
                  status != .legal else { return nil }
            return (group, status)
        }
    }

    private func legalityLabel(_ status: LegalityStatus) -> String {
        switch status {
        case .legal:    return "Legal"
        case .notLegal: return "Not legal"
        case .banned:   return "Banned"
        case .restricted: return "Restricted"
        }
    }

    @ViewBuilder
    private var legalityBanner: some View {
        let flagged = illegalGroups
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("\(flagged.count) not legal in \(deckFormat.displayName)")
                    .font(.subheadline.bold())
                    .foregroundStyle(MD3Theme.onSurface)
                HelpButton("Cards that are banned, restricted, or not printed in a legal set for the deck's selected format. Restricted = limited to 1 copy in the deck.")
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(flagged.enumerated()), id: \.offset) { idx, entry in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(entry.group.representative.cardName)
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurface)
                        Spacer()
                        Text(legalityLabel(entry.status))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    if idx < flagged.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Open Card Detail

    private func openCard(for item: PurchaseItem) async {
        guard let cardRepository, loadingCardItemID == nil else { return }
        loadingCardItemID = item.id
        defer { loadingCardItemID = nil }

        if let card = try? await cardRepository.fetchCard(set: item.setCode, collectorNumber: item.collectorNumber) {
            viewingCard = card
        } else if let card = try? await cardRepository.identifyCard(name: item.cardName) {
            // Fallback: any printing of the same card name
            viewingCard = card
        }
    }

    // MARK: - Grouping

    /// A group of PurchaseItem copies that share the same card identity (name + set + collector).
    struct CardGroup: Identifiable {
        let id: String // composite key
        let items: [PurchaseItem]
        var representative: PurchaseItem { items[0] }
        var quantity: Int { items.count }
    }

    /// Items grouped by card identity, sorted alphabetically by card name.
    private var groupedCards: [CardGroup] {
        let byKey = Dictionary(grouping: items) { item in
            "\(item.cardName)|\(item.setCode)|\(item.collectorNumber)"
        }
        return byKey
            .map { key, value in
                CardGroup(
                    id: key,
                    items: value.sorted { $0.addedAt < $1.addedAt }
                )
            }
            .sorted { $0.representative.cardName < $1.representative.cardName }
    }

    private var totalCards: Int { items.count }
    private var mainboardItems: [PurchaseItem] { items.filter { $0.zone == "mainboard" } }
    private var sideboardItems: [PurchaseItem] { items.filter { $0.zone == "sideboard" } }
    private var mainboardCount: Int { mainboardItems.count }
    private var sideboardCount: Int { sideboardItems.count }
    private var neededCount: Int { items.filter { $0.status == .needed }.count }
    private var orderedCount: Int { items.filter { $0.status == .ordered }.count }
    private var arrivedCount: Int { items.filter { $0.status == .arrived }.count }

    private var totalSpent: Double {
        items.compactMap { $0.pricePaid }.reduce(0, +)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("No cards yet")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Add cards from the card detail view by tapping \"Add to Deck\", or import a decklist below.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if cardRepository != nil {
                MD3FilledButton("Import Decklist") {
                    showImportSheet = true
                }
                .padding(.top, 8)
            }

            Spacer()
        }
    }

    // MARK: - List vs Grid

    @ViewBuilder
    private var listView: some View {
        List {
            Section {
                compactHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            // Show reference decklist link if available
            if let urlString = deck.referenceURL, let url = URL(string: urlString) {
                Section {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .foregroundStyle(MD3Theme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reference Decklist")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MD3Theme.onSurface)
                                Text("View on MTGTop8")
                                    .font(.caption2)
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(MD3Theme.primary)
                        }
                    }
                }
            }
            if !illegalGroups.isEmpty {
                Section {
                    legalityBanner
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            if let minSize = deckFormat.minDeckSize, mainboardCount < minSize {
                Section {
                    deckSizeBanner(minSize: minSize)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                if !suggestions.isEmpty || loadingSuggestions {
                    Section {
                        suggestionsList
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    } header: {
                        if let match = suggestionResult.archetypeMatch {
                            Text("Detected: \(match.archetype.name) (\(match.archetype.era)) · \(match.similarityPercent)% match")
                        } else {
                            Text("Suggested from tournament decks")
                        }
                    } footer: {
                        if let match = suggestionResult.archetypeMatch {
                            Text("\(match.archetype.description)\nSource: \(match.archetype.source)")
                                .font(.caption2)
                        }
                    }
                }
            }
            Section {
                DeckGuideView(
                    deckName: deck.name,
                    format: deck.format,
                    mainboard: items.filter { $0.zone == "mainboard" }.map { ($0.cardName, $0.quantity) },
                    sideboard: items.filter { $0.zone == "sideboard" }.map { ($0.cardName, $0.quantity) },
                    source: deck.referenceURL != nil ? "MTGTop8 tournament deck" : nil,
                    cardRepository: cardRepository
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
            ForEach(zoneSections) { zoneSection in
                Section {
                    zoneHeader(zoneSection)
                }
                ForEach(zoneSection.sections, id: \.category) { section in
                    Section {
                        let allZoneGroups = zoneSection.sections.flatMap(\.groups)
                        let pagerEntries = allZoneGroups.map {
                            CardCopiesPagerView.Entry(
                                id: $0.id,
                                cardName: $0.representative.cardName,
                                setCode: $0.representative.setCode,
                                collectorNumber: $0.representative.collectorNumber
                            )
                        }
                        ForEach(section.groups) { group in
                            NavigationLink {
                                if let cardRepository {
                                    let idx = allZoneGroups.firstIndex(where: { $0.id == group.id }) ?? 0
                                    CardCopiesPagerView(
                                        entries: pagerEntries,
                                        initialIndex: idx,
                                        deckRepository: repository,
                                        cardRepository: cardRepository,
                                        deckID: deck.id
                                    )
                                }
                            } label: {
                                cardRowCompact(group, zone: zoneSection.zone)
                            }
                            .swipeActions(edge: .trailing) {
                                let targetZone = zoneSection.zone == "mainboard" ? "sideboard" : "mainboard"
                                let label = zoneSection.zone == "mainboard" ? "Sideboard" : "Mainboard"
                                Button {
                                    try? repository.moveItems(group.items, toZone: targetZone)
                                    reload()
                                } label: {
                                    Label("→ \(label)", systemImage: targetZone == "sideboard" ? "arrow.right.square" : "arrow.left.square")
                                }
                                .tint(.indigo)
                            }
                        }
                    } header: {
                        sectionHeader(section.category, count: section.totalCopies)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var gridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                compactHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if loadingGridCards && resolvedCards.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Loading card images…")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else {
                    ForEach(zoneSections) { zoneSection in
                        zoneHeader(zoneSection)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        ForEach(zoneSection.sections, id: \.category) { section in
                            gridSection(section)
                        }
                    }
                }

                Color.clear.frame(height: 32)
            }
        }
    }

    @ViewBuilder
    private func gridSection(_ section: CategorySection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.category.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Text("(\(section.totalCopies))")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(section.groups) { group in
                        gridCard(group, section: section)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func gridCard(_ group: CardGroup, section: CategorySection? = nil) -> some View {
        let item = group.representative
        let card = resolvedCards[item.scryfallID]
        let arrived = group.items.filter { $0.status == .arrived }.count
        let sectionGroups = section?.groups ?? [group]
        let pagerEntries = sectionGroups.map {
            CardCopiesPagerView.Entry(
                id: $0.id,
                cardName: $0.representative.cardName,
                setCode: $0.representative.setCode,
                collectorNumber: $0.representative.collectorNumber
            )
        }
        let idx = sectionGroups.firstIndex(where: { $0.id == group.id }) ?? 0
        NavigationLink {
            if let cardRepository {
                CardCopiesPagerView(
                    entries: pagerEntries,
                    initialIndex: idx,
                    deckRepository: repository,
                    cardRepository: cardRepository,
                    deckID: deck.id
                )
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if let card, let url = imageURL(for: card) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                gridPlaceholder(item)
                            }
                        }
                    } else {
                        gridPlaceholder(item)
                    }

                    // Quantity badge
                    Text("\(group.quantity)")
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

                // Status indicator under the image
                progressFraction(arrived: arrived, ordered: group.items.filter { $0.status == .ordered }.count, total: group.quantity)
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
    }

    private func gridPlaceholder(_ item: PurchaseItem) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(MD3Theme.surfaceVariant)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .overlay(
                Text(item.cardName)
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
        guard let str else { return nil }
        return URL(string: str)
    }

    /// Lazy-loads `Card` objects for every unique printing in the deck.
    /// Caches by scryfallID so swapping back to grid mode is instant.
    private func loadGridCardsIfNeeded() async {
        guard viewMode == .grid else { return }
        let uniqueIDs = Set(items.map { "\($0.setCode)|\($0.collectorNumber)" })
        // Skip if everything is already cached
        let allCached = items.allSatisfy { resolvedCards[$0.scryfallID] != nil }
        if allCached { return }
        loadingGridCards = true
        defer { loadingGridCards = false }
        guard let cardRepository else { return }
        for key in uniqueIDs {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            // Find a representative item to get the scryfallID
            guard let rep = items.first(where: { $0.setCode == parts[0] && $0.collectorNumber == parts[1] }) else { continue }
            if resolvedCards[rep.scryfallID] != nil { continue }
            if let card = try? await cardRepository.fetchCard(set: parts[0], collectorNumber: parts[1]) {
                resolvedCards[rep.scryfallID] = card
            }
        }
    }

    // MARK: - Compact Header

    /// Single-line summary with a thin progress bar showing arrived / total.
    @ViewBuilder
    private var compactHeader: some View {
        let total = max(totalCards, 1)
        let progress = Double(arrivedCount) / Double(total)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(arrivedCount)/\(totalCards)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                Text("collected")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                if sideboardCount > 0 {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                    Text("\(mainboardCount) main + \(sideboardCount) side")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                HelpButton("\"Collected\" = cards already in hand (Arrived). The full lifecycle is Needed → Ordered → Arrived.")
                Spacer()
                if orderedCount > 0 {
                    HStack(spacing: 4) {
                        Label("\(orderedCount)", systemImage: "shippingbox.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                        HelpButton("Ordered: purchase placed, card is in flight from a store.", size: 11)
                    }
                }
                if neededCount > 0 {
                    HStack(spacing: 4) {
                        Label("\(neededCount)", systemImage: "cart")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        HelpButton("Needed: still on the wishlist. Not yet purchased.", size: 11)
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MD3Theme.outlineVariant)
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.green)
                        .frame(width: geo.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
            HStack(spacing: 12) {
                if let spentLabel = CurrencyTotals.format(spentByCurrency) {
                    HStack(spacing: 4) {
                        Image(systemName: "creditcard")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        Text("Spent: \(spentLabel)")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
                if ownedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        Text("Owned: \(ownedCount)/\(totalCards)")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
            }
        }
    }

    // MARK: - Categorized Sections

    struct CategorySection {
        let category: CardCategory
        let groups: [CardGroup]
        var totalCopies: Int { groups.reduce(0) { $0 + $1.quantity } }
    }

    /// A zone (mainboard / sideboard) containing its own categorized sections.
    struct ZoneSection: Identifiable {
        let zone: String          // "mainboard" or "sideboard"
        let sections: [CategorySection]
        var id: String { zone }
        var totalCopies: Int { sections.reduce(0) { $0 + $1.totalCopies } }
        var displayName: String { zone == "sideboard" ? "Sideboard" : "Mainboard" }
    }

    /// Items grouped by zone, then by card category within each zone.
    private var zoneSections: [ZoneSection] {
        let zones = ["mainboard", "sideboard"]
        return zones.compactMap { zone in
            let zoneItems = items.filter { $0.zone == zone }
            guard !zoneItems.isEmpty else { return nil }
            let groups = groupedCardsFor(items: zoneItems)
            let byCategory = Dictionary(grouping: groups) { group in
                CardCategory.from(typeLine: group.representative.typeLine)
            }
            let sections = byCategory
                .map { CategorySection(category: $0.key, groups: $0.value) }
                .sorted { $0.category.sortOrder < $1.category.sortOrder }
            return ZoneSection(zone: zone, sections: sections)
        }
    }

    /// Flat categorized sections (legacy, used by grid view).
    private var categorizedSections: [CategorySection] {
        let groups = groupedCards
        let byCategory = Dictionary(grouping: groups) { group in
            CardCategory.from(typeLine: group.representative.typeLine)
        }
        return byCategory
            .map { CategorySection(category: $0.key, groups: $0.value) }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }

    /// Groups items by card identity, sorted alphabetically.
    private func groupedCardsFor(items zoneItems: [PurchaseItem]) -> [CardGroup] {
        let byKey = Dictionary(grouping: zoneItems) { item in
            "\(item.cardName)|\(item.setCode)|\(item.collectorNumber)"
        }
        return byKey
            .map { key, value in
                CardGroup(
                    id: key,
                    items: value.sorted { $0.addedAt < $1.addedAt }
                )
            }
            .sorted { $0.representative.cardName < $1.representative.cardName }
    }

    @ViewBuilder
    private func sectionHeader(_ category: CardCategory, count: Int) -> some View {
        HStack {
            Text(category.rawValue.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.7))
            Spacer()
        }
    }

    @ViewBuilder
    private func zoneHeader(_ zoneSection: ZoneSection) -> some View {
        HStack {
            Text(zoneSection.displayName.uppercased())
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MD3Theme.onSurface)
            Text("(\(zoneSection.totalCopies))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Spacer()
        }
    }

    // MARK: - Compact Card Row

    @ViewBuilder
    private func cardRowCompact(_ group: CardGroup, zone: String = "mainboard") -> some View {
        let item = group.representative
        let arrived = group.items.filter { $0.status == .arrived }.count
        let ordered = group.items.filter { $0.status == .ordered }.count
        // Pick the first copy with a recorded price for the per-card spend line.
        let pricedCopy = group.items.first { $0.pricePaid != nil }
        // Pick the earliest non-nil ETA across the group's ordered copies.
        let earliestETA: Date? = group.items
            .compactMap { $0.order?.eta }
            .min()
        HStack(spacing: 12) {
            Text("\(group.quantity)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .frame(minWidth: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isFlagged(item) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    Text(item.cardName)
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)
                    if let manaCost = item.manaCost, !manaCost.isEmpty {
                        ManaCostView(cost: manaCost, size: 13)
                    }
                    if item.isFoil {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(item.setName) · #\(item.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
                if pricedCopy != nil || earliestETA != nil {
                    HStack(spacing: 6) {
                        if let pricedCopy, let price = pricedCopy.pricePaid {
                            Text("\(pricedCopy.currency ?? "USD") \(MoneyFormat.compact(price)) ea")
                                .font(.caption2)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                        if let earliestETA {
                            Label("ETA \(ShortDate.format(earliestETA))", systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            progressFraction(arrived: arrived, ordered: ordered, total: group.quantity)
        }
        .padding(.vertical, 4)
        .contextMenu {
            if cardRepository != nil {
                Button {
                    changePrintingItem = item
                } label: {
                    Label("Change Printing", systemImage: "rectangle.stack")
                }
            }
            let targetZone = zone == "mainboard" ? "sideboard" : "mainboard"
            let moveOneLabel = zone == "mainboard" ? "Move 1 to Sideboard" : "Move 1 to Mainboard"
            let moveAllLabel = zone == "mainboard" ? "Move All to Sideboard" : "Move All to Mainboard"
            let zoneIcon = zone == "mainboard" ? "arrow.right.square" : "arrow.left.square"
            // Move one copy
            Button {
                if let first = group.items.first {
                    try? repository.moveItems([first], toZone: targetZone)
                    reload()
                }
            } label: {
                Label(moveOneLabel, systemImage: zoneIcon)
            }
            // Move all copies (only show when > 1)
            if group.items.count > 1 {
                Button {
                    try? repository.moveItems(group.items, toZone: targetZone)
                    reload()
                } label: {
                    Label(moveAllLabel, systemImage: "arrow.right.square.fill")
                }
            }
            Divider()
            // Foil toggle
            Button {
                let newFoil = !(group.items.first?.isFoil ?? false)
                for copy in group.items {
                    copy.isFoil = newFoil
                }
                reload()
            } label: {
                if group.items.first?.isFoil == true {
                    Label("Mark as Non-Foil", systemImage: "sparkles")
                } else {
                    Label("Mark as Foil", systemImage: "sparkles")
                }
            }
            Divider()
            // Add/remove copies
            if let card = resolvedCards[group.items.first?.cardName ?? ""] {
                Button {
                    try? repository.addItem(card: card, quantity: 1, to: deck, zone: zone)
                    reload()
                } label: {
                    Label("Add Copy", systemImage: "plus.circle")
                }
            }
            if group.items.count > 1 {
                Button {
                    if let last = group.items.last {
                        try? repository.deleteItem(last)
                        reload()
                    }
                } label: {
                    Label("Remove Copy", systemImage: "minus.circle")
                }
            }
            Button(role: .destructive) {
                for copy in group.items {
                    try? repository.deleteItem(copy)
                }
                reload()
            } label: {
                Label("Delete All", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func progressFraction(arrived: Int, ordered: Int, total: Int) -> some View {
        let allArrived = arrived == total
        HStack(spacing: 6) {
            if ordered > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(ordered)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.orange)
            }
            HStack(spacing: 4) {
                if allArrived {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                }
                Text("\(arrived)/\(total)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(allArrived ? .green : MD3Theme.onSurfaceVariant)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Suggest Sideboard

    /// Curated list of card names that are almost always sideboard cards across
    /// competitive formats. Lowercase for case-insensitive matching.
    private static let typicalSideboardCards: Set<String> = [
        // Graveyard hate
        "relic of progenitus", "tormod's crypt", "rest in peace",
        "surgical extraction", "leyline of the void", "grafdigger's cage",
        "soul-guide lantern", "endurance", "unlicensed hearse",
        "faerie macabre", "ravenous trap",
        // Artifact / enchantment removal
        "nature's claim", "force of vigor", "stony silence", "null rod",
        "collector ouphe", "kataki, war's wage", "hurkyl's recall",
        "shatterstorm", "seeds of innocence", "energy flux",
        "back to nature", "fracturing gust",
        // Extra counterspells
        "spell pierce", "flusterstorm", "negate", "dispel",
        "veil of summer", "mystical dispute", "dovin's veto",
        "pyroblast", "red elemental blast", "hydroblast",
        "blue elemental blast", "aether gust",
        // Removal
        "dismember", "path to exile", "wear // tear",
        "ancient grudge", "abrade", "brotherhood's end",
        // Anti-aggro / lifegain
        "weather the storm", "dragon's claw", "kor firewalker",
        "timely reinforcements", "sun droplet", "blessed alliance",
        "sunset revelry",
        // Discard
        "thoughtseize", "duress", "inquisition of kozilek",
        // Hate pieces
        "pithing needle", "chalice of the void", "damping sphere",
        "torpor orb", "trinisphere", "ensnaring bridge",
        "blood moon", "magus of the moon", "choke",
        "boil", "carpet of flowers",
        // Common sideboard threats / silver bullets
        "engineered explosives", "ratchet bomb", "oblivion stone",
        "containment priest", "sanctifier en-vec", "plague engineer",
        "opposition agent", "ashiok, dream render",
    ]

    /// Moves cards from mainboard to sideboard if they match the curated
    /// sideboard list. Only touches mainboard cards, and only when mainboard
    /// has > 60 cards. Stops moving once mainboard reaches 60 or sideboard
    /// reaches 15.
    private func suggestSideboard() {
        let mainboard = items.filter { $0.zone == "mainboard" }

        let candidates = mainboard.filter { item in
            Self.typicalSideboardCards.contains(item.cardName.lowercased())
        }

        guard !candidates.isEmpty else {
            sideboardSuggestCount = 0
            withAnimation { showSideboardSuggestToast = true }
            return
        }

        // Group by card name, default moveCount to total available
        let grouped = Dictionary(grouping: candidates) { $0.cardName }
        sideboardCandidates = grouped
            .map { (name: $0.key, items: $0.value, moveCount: $0.value.count) }
            .sorted { $0.name < $1.name }
        showSideboardPicker = true
    }

    private func applySideboardSelections() {
        var movedTotal = 0
        for candidate in sideboardCandidates where candidate.moveCount > 0 {
            let toMove = Array(candidate.items.prefix(candidate.moveCount))
            try? repository.moveItems(toMove, toZone: "sideboard")
            movedTotal += toMove.count
        }
        reload()
        sideboardSuggestCount = movedTotal
        showSideboardPicker = false
        withAnimation { showSideboardSuggestToast = true }
    }

    // MARK: - Sideboard Picker Sheet

    private var sideboardPickerSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select how many copies of each card to move to the sideboard.")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                ForEach($sideboardCandidates, id: \.name) { $candidate in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name)
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(candidate.items.count) in mainboard")
                                .font(.caption2)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                candidate.moveCount = max(0, candidate.moveCount - 1)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(candidate.moveCount > 0 ? MD3Theme.primary : Color.gray.opacity(0.3))
                            }
                            .disabled(candidate.moveCount <= 0)

                            Text("\(candidate.moveCount)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .frame(minWidth: 24)
                                .monospacedDigit()

                            Button {
                                candidate.moveCount = min(candidate.items.count, candidate.moveCount + 1)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(candidate.moveCount < candidate.items.count ? MD3Theme.primary : Color.gray.opacity(0.3))
                            }
                            .disabled(candidate.moveCount >= candidate.items.count)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Move to Sideboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSideboardPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let total = sideboardCandidates.reduce(0) { $0 + $1.moveCount }
                    Button("Move \(total)") { applySideboardSelections() }
                        .disabled(total == 0)
                }
            }
        }
    }

    // MARK: - Change All Printings

    /// Resolves every card in the deck to the chosen printing strategy and
    /// updates each PurchaseItem's printing fields accordingly.
    private func changeAllPrintings(to strategy: PrintingStrategy) async {
        guard let cardRepository else { return }
        changingAllPrintings = true
        defer { changingAllPrintings = false }

        let resolver = CardResolver(cardRepository: cardRepository)

        // Collect unique card names to resolve in batch.
        let uniqueNames = Array(Set(items.map { $0.cardName }))
        let resolved = await resolver.resolveAll(names: uniqueNames, strategy: strategy)

        // Apply resolved printings to each item.
        for item in items {
            guard let card = resolved[item.cardName] else { continue }
            // Skip if already pointing at the same printing.
            if item.scryfallID == card.scryfallID { continue }
            try? repository.changePrinting(item, to: card)
        }

        reload()
    }

    // MARK: - Actions

    // MARK: - AI Fix Deck (60+15)

    private func aiFixDeck() async {
        isFixingDeck = true
        fixDeckError = nil
        defer { isFixingDeck = false }

        let mainItems = items.filter { $0.zone == "mainboard" }
        let mainList = Dictionary(grouping: mainItems, by: \.cardName)
            .map { "\($0.value.count)x \($0.key)" }
            .sorted()
            .joined(separator: ", ")
        let formatStr = deck.format ?? "Unknown"

        let prompt = """
        You are an expert MTG deck builder. This deck has \(mainItems.count) cards in the mainboard but should have 60 mainboard + 15 sideboard.

        Deck: \(deck.name)
        Format: \(formatStr)
        All cards currently in mainboard: \(mainList)

        Return ONLY a JSON array of card names to MOVE to sideboard (the 15 cards that should become the sideboard). Choose the most situational/matchup-dependent cards.
        Example: ["Card Name 1", "Card Name 2", ...]
        Return exactly 15 card names (accounting for quantities). Use exact card names from the list above. No other text.
        """

        guard let result = await GeminiVisionService.generateInsight(prompt: prompt) else {
            fixDeckError = "Failed to get AI suggestion. Try again."
            return
        }

        let cleaned = result
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let cardNames = try? JSONSerialization.jsonObject(with: data) as? [String],
              !cardNames.isEmpty else {
            fixDeckError = "AI response was incomplete. Try again."
            return
        }

        // Move the specified cards to sideboard
        var moved = 0
        for name in cardNames {
            let lowerName = name.lowercased()
            // Find a mainboard item with this name that hasn't been moved yet
            if let item = items.first(where: {
                $0.cardName.lowercased() == lowerName && $0.zone == "mainboard"
            }) {
                try? repository.moveItems([item], toZone: "sideboard")
                moved += 1
            }
        }

        reload()

        if moved > 0 {
            fixDeckError = nil
        } else {
            fixDeckError = "No matching cards found to move."
        }
    }

    private func reload() {
        // Refetch via the repository so we see items added in other contexts
        // (e.g., from ImportDecklistSheet). `deck.items` may be stale.
        items = (try? repository.fetchItems(deckID: deck.id)) ?? []
        spentByCurrency = (try? repository.totalSpent(deckID: deck.id)) ?? [:]
        // Compute "owned from collection" count.
        if let owned = try? repository.ownedQuantitiesByScryfallID() {
            // For each printing the deck wants, take min(deckQty, ownedQty).
            var deckCounts: [String: Int] = [:]
            for item in items {
                deckCounts[item.scryfallID, default: 0] += 1
            }
            var matched = 0
            for (id, deckQty) in deckCounts {
                let ownedQty = owned[id] ?? 0
                matched += min(deckQty, ownedQty)
            }
            ownedCount = matched
        } else {
            ownedCount = 0
        }
    }
}

// MARK: - Sideboard Guide Sheet

struct SideboardGuideSheet: View {
    let format: DeckFormat
    /// Lowercased card names from the user's sideboard.
    let sideboardCards: [String]

    @Environment(\.dismiss) private var dismiss

    private var matchupPlans: [SideboardPlan] {
        SideboardGuideData.plans(for: format.rawValue)
    }

    private func userHas(_ recommendation: String) -> Bool {
        let lower = recommendation.lowercased()
        return sideboardCards.contains { card in
            card.contains(lower) || lower.contains(card)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if matchupPlans.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "book.pages")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No sideboard data for \(format.displayName)")
                                .font(.headline)
                            Text("Sideboard guides are available for Modern, Legacy, and Pioneer.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    Section {
                        Text("\(format.displayName) — \(matchupPlans.count) matchups")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(matchupPlans) { plan in
                        Section {
                            DisclosureGroup {
                                matchupDetail(plan)
                            } label: {
                                HStack {
                                    Text(plan.opponent)
                                        .font(.headline)
                                    Spacer()
                                    Text(plan.opponentType)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(badgeColor(for: plan.opponentType).opacity(0.15))
                                        .foregroundStyle(badgeColor(for: plan.opponentType))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Section("General Principles") {
                        ForEach(SideboardGuideData.generalPrinciples) { principle in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label {
                                        Text(principle.bringIn)
                                            .font(.subheadline)
                                    } icon: {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                    }
                                    Label {
                                        Text(principle.takeOut)
                                            .font(.subheadline)
                                    } icon: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                            .font(.caption)
                                    }
                                    Text(principle.principle)
                                        .font(.subheadline)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 4)
                                }
                                .padding(.vertical, 4)
                            } label: {
                                Text("vs \(principle.againstType)")
                                    .font(.headline)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sideboard Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func matchupDetail(_ plan: SideboardPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Bring In
            VStack(alignment: .leading, spacing: 4) {
                Text("Bring IN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                ForEach(plan.bringIn, id: \.self) { card in
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                        Text(card)
                            .font(.subheadline)
                        Spacer()
                        if !sideboardCards.isEmpty {
                            if userHas(card) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            Divider()

            // Take Out
            VStack(alignment: .leading, spacing: 4) {
                Text("Take OUT")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                ForEach(plan.takeOut, id: \.self) { card in
                    HStack(spacing: 6) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption2)
                        Text(card)
                            .font(.subheadline)
                    }
                }
            }

            Divider()

            // Strategy
            Text(plan.strategy)
                .font(.subheadline)
                .italic()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func badgeColor(for type: String) -> Color {
        let lower = type.lowercased()
        if lower.contains("aggro") { return .red }
        if lower.contains("combo") { return .purple }
        if lower.contains("control") { return .blue }
        if lower.contains("midrange") { return .orange }
        if lower.contains("tempo") { return .teal }
        if lower.contains("ramp") { return .green }
        if lower.contains("prison") { return .gray }
        if lower.contains("artifact") { return .brown }
        return .secondary
    }
}

// MARK: - Card Copies Pager View

/// Horizontal paging view that wraps `CardCopiesDetailView` instances,
/// letting the user swipe left/right to browse cards in a deck.
struct CardCopiesPagerView: View {

    struct Entry: Identifiable {
        let id: String
        let cardName: String
        let setCode: String
        let collectorNumber: String
    }

    let entries: [Entry]
    let initialIndex: Int
    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol
    let deckID: UUID

    @State private var currentIndex: Int = 0

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                CardCopiesDetailView(
                    cardName: entry.cardName,
                    setCode: entry.setCode,
                    collectorNumber: entry.collectorNumber,
                    deckRepository: deckRepository,
                    cardRepository: cardRepository,
                    deckID: deckID
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .onAppear { currentIndex = initialIndex }
        .navigationTitle(entries.indices.contains(currentIndex) ? entries[currentIndex].cardName : "")
        .navigationBarTitleDisplayMode(.inline)
    }
}
