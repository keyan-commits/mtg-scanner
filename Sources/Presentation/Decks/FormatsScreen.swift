import SwiftUI

/// Per-format MTGTop8 archetype browser. Lists every archetype
/// MTGTop8 has indexed for the selected format, with each row showing
/// the most recent #1-finish deck. Tapping a row opens the full
/// decklist in `MTGTop8DeckDetailView`.
///
/// This is the "Formats" home entry — for the merged-by-name umbrella
/// view, see `BrowseArchetypesScreen`.
struct FormatsScreen: View {

    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    private let archetypeIndex: MTGTop8ArchetypeIndexProtocol
    private let topFinishesCache: LatestTopFinishesCacheProtocol

    @State private var allArchetypes: [IndexedArchetype] = []
    @State private var isLoadingCatalog: Bool = true
    @State private var catalogError: String?
    @State private var selectedFormat: MTGTop8Format = .modern
    @State private var showingRefreshConfirm: Bool = false

    init(
        cardRepository: CardRepositoryProtocol,
        deckRepository: DeckListRepository,
        archetypeIndex: MTGTop8ArchetypeIndexProtocol = MTGTop8ArchetypeIndex(),
        topFinishesCache: LatestTopFinishesCacheProtocol = LatestTopFinishesCache()
    ) {
        self.cardRepository = cardRepository
        self.deckRepository = deckRepository
        self.archetypeIndex = archetypeIndex
        self.topFinishesCache = topFinishesCache
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoadingCatalog && allArchetypes.isEmpty {
                loadingState
            } else if let catalogError, allArchetypes.isEmpty {
                errorState(catalogError)
            } else {
                content
            }
        }
        .navigationTitle("Formats")
        .navigationBarTitleDisplayMode(.inline)
        .background(MD3Theme.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingRefreshConfirm = true
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoadingCatalog)
            }
        }
        .confirmationDialog(
            "Refresh archetype data?",
            isPresented: $showingRefreshConfirm,
            titleVisibility: .visible
        ) {
            Button("Refresh All", role: .destructive) {
                Task { await refreshEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Re-fetches the archetype catalog from MTGTop8 and clears every cached top-1 deck. Takes a few seconds.")
        }
        .task {
            await loadCatalog()
        }
    }

    // MARK: - Loading + error

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading archetypes from MTGTop8…")
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
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") {
                Task { await loadCatalog(forceRefresh: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            formatPicker
            Divider()
            archetypeList
        }
    }

    private var formatPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MTGTop8Format.allCases) { format in
                    Button {
                        selectedFormat = format
                    } label: {
                        Text(format.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedFormat == format ? MD3Theme.onPrimary : MD3Theme.onSurfaceVariant)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedFormat == format ? MD3Theme.primary : MD3Theme.surfaceVariant)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(MD3Theme.background)
    }

    /// Pre-grouped and pre-sorted archetypes by format (avoids re-sorting on every format tap).
    @State private var archetypesByFormat: [MTGTop8Format: [IndexedArchetype]] = [:]

    private var archetypesForSelectedFormat: [IndexedArchetype] {
        archetypesByFormat[selectedFormat] ?? []
    }

    private func buildFormatIndex() {
        var grouped: [MTGTop8Format: [IndexedArchetype]] = [:]
        for arch in allArchetypes {
            grouped[arch.format, default: []].append(arch)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        archetypesByFormat = grouped
    }

    @ViewBuilder
    private var archetypeList: some View {
        let archetypes = archetypesForSelectedFormat
        if archetypes.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Text("No archetypes for \(selectedFormat.displayName)")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(archetypes.enumerated()), id: \.element.id) { idx, archetype in
                        ArchetypeRow(
                            archetype: archetype,
                            cardRepository: cardRepository,
                            deckRepository: deckRepository,
                            cache: topFinishesCache
                        )
                        if idx < archetypes.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(MD3Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(16)
            }
            .refreshable {
                await refreshVisibleFormat()
            }
        }
    }

    // MARK: - Loading actions

    private func loadCatalog(forceRefresh: Bool = false) async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            allArchetypes = try await archetypeIndex.archetypes(forceRefresh: forceRefresh)
            buildFormatIndex()
            catalogError = nil
        } catch {
            catalogError = "Could not load archetype catalog from MTGTop8."
        }
    }

    /// Pull-to-refresh handler — wipes the cached top-1 entries for
    /// archetypes in the currently-selected format. The rows then
    /// re-fetch in their `.task` modifiers as the list re-renders.
    private func refreshVisibleFormat() async {
        // Simplest correct behavior: clear the entire cache. The
        // visible format's rows will refetch immediately; other
        // formats refetch lazily when next viewed.
        await topFinishesCache.clearAll()
        // Force a re-render so each row's `.task` runs again.
        let snapshot = allArchetypes
        allArchetypes = []
        try? await Task.sleep(nanoseconds: 50_000_000)
        allArchetypes = snapshot
    }

    /// Toolbar "Refresh All" — wipes both caches and reloads the
    /// archetype catalog from scratch.
    private func refreshEverything() async {
        await topFinishesCache.clearAll()
        await loadCatalog(forceRefresh: true)
    }
}

// MARK: - Row

/// One archetype row. Owns its own state for the lazy top-1 lookup
/// so each row can independently load, retry, and display.
private struct ArchetypeRow: View {

    let archetype: IndexedArchetype
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository
    let cache: LatestTopFinishesCacheProtocol

    @State private var topDeck: MTGTop8Deck?
    @State private var isLoading: Bool = true
    @State private var loadFailed: Bool = false

    var body: some View {
        NavigationLink {
            if let topDeck {
                MTGTop8DeckDetailView(
                    deckID: topDeck.deckID,
                    deckName: topDeck.name,
                    player: topDeck.player,
                    format: archetype.format.displayName,
                    cardRepository: cardRepository,
                    deckRepository: deckRepository
                )
            } else {
                // Fall back to the generic archetype view if we
                // don't have a top-1 deck (no recent winners).
                ArchetypeDecksView(
                    archetype: archetype.name,
                    format: archetype.format.displayName,
                    source: .online(
                        archetypeID: archetype.archetypeID,
                        formatCode: archetype.format.code
                    ),
                    cardRepository: cardRepository,
                    deckRepository: deckRepository
                )
            }
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .task {
            await loadTopDeck()
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(MD3Theme.primaryContainer)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MD3Theme.primary)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(archetype.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                topDeckSubtitle
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var topDeckSubtitle: some View {
        if isLoading {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.5)
                Text("Loading latest #1…")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        } else if let topDeck {
            HStack(spacing: 4) {
                if topDeck.level > 0 {
                    rowStars(level: topDeck.level)
                }
                Text(topDeckCaption(topDeck))
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
            }
        } else if loadFailed {
            Text("Couldn't fetch latest #1")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else {
            Text("No recent #1 finish")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.7))
        }
    }

    private func topDeckCaption(_ deck: MTGTop8Deck) -> String {
        var parts: [String] = []
        if !deck.player.isEmpty { parts.append(deck.player) }
        if !deck.event.isEmpty { parts.append(deck.event) }
        if !deck.date.isEmpty { parts.append(deck.date) }
        return parts.joined(separator: " · ")
    }

    /// Inline mini-stars used inside the row caption.
    @ViewBuilder
    private func rowStars(level: Int) -> some View {
        let clamped = max(0, min(5, level))
        HStack(spacing: 1) {
            ForEach(0..<clamped, id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityLabel("\(clamped) star tournament")
    }

    private func loadTopDeck() async {
        isLoading = true
        loadFailed = false
        let deck = await cache.latestTop1(
            archetypeID: archetype.archetypeID,
            format: archetype.format.code,
            forceRefresh: false
        )
        topDeck = deck
        isLoading = false
        // We can't distinguish "fetch failed" from "no recent #1" via
        // the cache API alone. Treat nil as the latter — the row UI
        // shows "No recent #1 finish" which covers both cases.
    }
}
