import SwiftUI

/// Lists all user-owned decks. Tap a deck to see its purchase checklist.
struct DecksScreen: View {

    let repository: DeckListRepository
    let cardRepository: CardRepositoryProtocol?

    @Bindable private var currencyService = CurrencyService.shared
    @State private var decks: [DeckList] = []
    @State private var analyses: [CardAnalysis] = []
    @State private var showCreateSheet = false
    @State private var newDeckName = ""
    @State private var newDeckFormat: DeckFormat = .freeform
    @State private var navigateToNewDeck: DeckList?
    @State private var editingDeck: DeckList?
    @State private var editDeckName = ""
    @State private var editDeckFormat: DeckFormat = .freeform
    @State private var iconPickerDeck: DeckList?
    @State private var showDeckBuilder = false
    /// Cached art-crop URL per deck.id for the row thumbnail.
    @State private var deckArtURLs: [UUID: URL] = [:]

    var body: some View {
        Group {
            if decks.isEmpty {
                emptyState
            } else {
                List {
                    if !analyses.isEmpty {
                        Section {
                            ForEach(analyses) { analysis in
                                NavigationLink(destination: CardAnalysisDetailView(
                                    analysis: analysis,
                                    deckRepository: repository,
                                    cardRepository: cardRepository
                                )) {
                                    analysisRow(analysis)
                                }
                            }
                            .onDelete(perform: deleteAnalyses)
                        } header: {
                            Text("Card Analyses")
                        }
                    }

                    Section {
                        ForEach(decks) { deck in
                            NavigationLink(destination: DeckDetailView(deck: deck, repository: repository, cardRepository: cardRepository)) {
                                deckRow(deck)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    beginEditing(deck)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    beginEditing(deck)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                if cardRepository != nil {
                                    Button {
                                        iconPickerDeck = deck
                                    } label: {
                                        Label("Choose Icon", systemImage: "photo.on.rectangle")
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteDecks)
                    } header: {
                        if !analyses.isEmpty {
                            Text("Decks")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("My Decks")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    ScreenHelpButton(title: "My Decks", sections: [
                        HelpSection(icon: "plus", title: "Create a new deck",
                                    body: "Tap the + button. Pick a format to enable legality validation; pick Freeform for vintage / casual decks where you don't want any restrictions."),
                        HelpSection(icon: "pencil", title: "Edit a deck",
                                    body: "Swipe right on a row or long-press it to open Edit. You can rename it or change its format any time — the legality banner inside the deck updates automatically."),
                        HelpSection(icon: "trash", title: "Delete a deck",
                                    body: "Swipe left to delete. The cards inside are also removed. There's no undo, so don't delete a deck just to fix a typo — use Edit instead."),
                        HelpSection(icon: "creditcard", title: "Spent line",
                                    body: "Each row shows total spend by currency once you've ordered any cards. \"Spent: PHP 4770\" means you've recorded that much in PHP for this deck."),
                    ])
                    if cardRepository != nil {
                        Button {
                            showDeckBuilder = true
                        } label: {
                            Image(systemName: "hammer")
                        }
                    }
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createDeckSheet
        }
        .sheet(item: $editingDeck) { deck in
            editDeckSheet(deck)
        }
        .sheet(item: $iconPickerDeck) { deck in
            if let cardRepository {
                ChooseDeckIconSheet(
                    deck: deck,
                    deckRepository: repository,
                    cardRepository: cardRepository
                ) {
                    iconPickerDeck = nil
                    // Bust the cached art URL so the new pick reloads
                    deckArtURLs[deck.id] = nil
                    Task { await loadDeckArt() }
                }
            }
        }
        .sheet(isPresented: $showDeckBuilder) {
            if let cardRepository {
                DeckBuilderScreen(
                    cardRepository: cardRepository,
                    deckRepository: repository
                )
            }
        }
        .navigationDestination(item: $navigateToNewDeck) { deck in
            DeckDetailView(
                deck: deck,
                repository: repository,
                cardRepository: cardRepository,
                autoOpenImport: true
            )
        }
        .onAppear { reload() }
        .onChange(of: showDeckBuilder) { _, isShowing in
            if !isShowing { reload() }  // Refresh after dismissing deck builder
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("No decks yet")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Create a deck to start tracking the cards you need to buy.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            MD3FilledButton("Create Deck") {
                showCreateSheet = true
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Deck Row

    private func deckRow(_ deck: DeckList) -> some View {
        let total = deck.items.count
        let needed = deck.items.filter { $0.status == .needed }.count
        let ordered = deck.items.filter { $0.status == .ordered }.count
        let arrived = deck.items.filter { $0.status.isCollected }.count
        let spentTotals = (try? repository.totalSpent(deckID: deck.id)) ?? [:]
        let spentLabel = CurrencyTotals.format(spentTotals)
        // TCGMid market value: sum of priceAtAddUSD across all items
        // (Scryfall USD price snapshot at the time each card was added)
        let marketUSD = deck.items.compactMap(\.priceAtAddUSD).reduce(0, +)

        return HStack(spacing: 12) {
            deckThumbnail(deck)
            VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(deck.name)
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
                if let format = deck.format, !format.isEmpty {
                    Text(DeckFormat.from(stored: format).displayName)
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(MD3Theme.onSecondaryContainer)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(MD3Theme.secondaryContainer)
                        .clipShape(Capsule())
                }
            }
            if total > 0 {
                HStack(spacing: 12) {
                    statusBadge("Needed", count: needed, color: MD3Theme.error)
                    statusBadge("Ordered", count: ordered, color: .orange)
                    statusBadge("Arrived", count: arrived, color: .green)
                }
                HStack(spacing: 12) {
                    if marketUSD > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                                .font(.caption2)
                                .foregroundStyle(MD3Theme.primary)
                            let preferred = LocalCurrency.current
                            if preferred != "USD",
                               let converted = currencyService.convert(marketUSD, to: preferred) {
                                Text("TCGMid: \(LocalCurrency.format(converted, currency: preferred)) · $\(String(format: "%.2f", marketUSD))")
                                    .font(MD3Typography.labelSmall)
                                    .foregroundStyle(MD3Theme.primary)
                                    .monospacedDigit()
                            } else {
                                Text("TCGMid: $\(String(format: "%.2f", marketUSD))")
                                    .font(MD3Typography.labelSmall)
                                    .foregroundStyle(MD3Theme.primary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    if let spentLabel {
                        HStack(spacing: 4) {
                            Image(systemName: "creditcard")
                                .font(.caption2)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                            Text("Spent: \(spentLabel)")
                                .font(MD3Typography.labelSmall)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                    }
                }
            } else {
                Text("Empty")
                    .font(MD3Typography.bodySmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            } // inner VStack
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func deckThumbnail(_ deck: DeckList) -> some View {
        ZStack {
            if let url = deckArtURLs[deck.id] {
                CachedPhaseImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MD3Theme.outlineVariant, lineWidth: 1)
        )
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            MD3Theme.surfaceVariant
            Image(systemName: "rectangle.stack")
                .font(.body)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    /// Lazily fetches an art-crop URL for each deck's signature card.
    /// Cached so re-renders are free.
    private func loadDeckArt() async {
        guard let cardRepository else { return }
        for deck in decks {
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

    private func statusBadge(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(MD3Typography.labelSmall)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    // MARK: - Analysis Row

    private func analysisRow(_ analysis: CardAnalysis) -> some View {
        let results = analysis.formatResults
        let best = results.first

        return HStack(spacing: 12) {
            ZStack {
                MD3Theme.surfaceVariant
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.body)
                    .foregroundStyle(MD3Theme.primary)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(analysis.title)
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)

                Text(analysis.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(MD3Typography.bodySmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)

                if let best {
                    HStack(spacing: 8) {
                        Text(best.displayName)
                            .font(MD3Typography.labelSmall)
                            .foregroundStyle(MD3Theme.onSecondaryContainer)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(MD3Theme.secondaryContainer)
                            .clipShape(Capsule())
                        Text("\(Int(best.percentage))% match")
                            .font(MD3Typography.labelSmall)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Create Deck Sheet

    private var createDeckSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck Name", text: $newDeckName)
                    Picker("Format", selection: $newDeckFormat) {
                        ForEach(DeckFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                } header: {
                    Text("Deck Info")
                } footer: {
                    Text(formatPickerFooter)
                        .font(.caption2)
                }
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showCreateSheet = false
                        newDeckName = ""
                        newDeckFormat = .freeform
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        createDeck()
                    }
                    .disabled(newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Edit Deck Sheet

    private func editDeckSheet(_ deck: DeckList) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck Name", text: $editDeckName)
                    Picker("Format", selection: $editDeckFormat) {
                        ForEach(DeckFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                } header: {
                    Text("Deck Info")
                } footer: {
                    Text(formatPickerFooter)
                        .font(.caption2)
                }
            }
            .navigationTitle("Edit Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        editingDeck = nil
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveEdit(deck)
                    }
                    .disabled(editDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var formatPickerFooter: String {
        """
        Freeform: any card allowed (no validation).
        Standard: newest sets, rotates yearly.
        Pioneer: 2012+. Modern: 2003+.
        Legacy: nearly all cards. Vintage: all cards (some restricted).
        Pauper: commons only. Commander: 100-card singleton.
        Premodern: pre-2003. Picking a non-Freeform format flags any cards in the deck that aren't legal in it.
        """
    }

    private func beginEditing(_ deck: DeckList) {
        editDeckName = deck.name
        editDeckFormat = DeckFormat.from(stored: deck.format)
        editingDeck = deck
    }

    private func saveEdit(_ deck: DeckList) {
        let trimmed = editDeckName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let stored = editDeckFormat == .freeform ? nil : editDeckFormat.rawValue
        try? repository.renameDeck(deck, name: trimmed, format: stored)
        editingDeck = nil
        reload()
    }

    // MARK: - Actions

    private func reload() {
        decks = (try? repository.fetchAllDecks()) ?? []
        analyses = (try? repository.fetchAnalyses()) ?? []
        Task { await loadDeckArt() }
    }

    private func createDeck() {
        let trimmedName = newDeckName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let stored = newDeckFormat == .freeform ? nil : newDeckFormat.rawValue
        guard let newDeck = try? repository.createDeck(
            name: trimmedName,
            format: stored
        ) else { return }
        newDeckName = ""
        newDeckFormat = .freeform
        showCreateSheet = false
        reload()
        // Push the new deck so the user can immediately import a decklist
        navigateToNewDeck = newDeck
    }

    private func deleteDecks(at offsets: IndexSet) {
        for index in offsets {
            try? repository.deleteDeck(decks[index])
        }
        reload()
    }

    private func deleteAnalyses(at offsets: IndexSet) {
        for index in offsets {
            try? repository.deleteAnalysis(analyses[index])
        }
        reload()
    }
}
