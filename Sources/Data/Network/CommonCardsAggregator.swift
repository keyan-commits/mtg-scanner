import Foundation

// MARK: - Models

/// One row in a common-cards list — a card name plus how many times
/// it appears across the relevant deck slice (universal across all
/// formats, or unique to one format).
struct CommonCardEntry: Codable, Sendable, Identifiable, Equatable {
    let cardName: String
    /// Sum of `quantity * deckCount` across every aggregated deck in
    /// the relevant slice.
    let totalCopies: Int
    /// How many distinct decks contained this card.
    let deckCount: Int

    var id: String { cardName }
}

/// One archetype variant that contributed to the aggregation, plus
/// metadata about which deck was sampled. Used by the detail view to
/// show "we aggregated from these N decks" so the user knows where
/// the data came from.
struct AggregationSource: Codable, Sendable, Identifiable, Equatable {
    let archetypeName: String
    let format: String
    let deckID: String
    let player: String
    let event: String
    let date: String

    var id: String { deckID }
}

/// One per-format slice of the aggregation: cards that appear in this
/// format's decks but NOT in the universal set across all formats.
struct PerFormatBreakdown: Codable, Sendable, Identifiable, Equatable {
    let formatCode: String
    let formatName: String
    let cards: [CommonCardEntry]

    var id: String { formatCode }
}

/// Output of `CommonCardsAggregator.aggregate(...)`. Contains the
/// universal core cards (present in EVERY format the archetype exists
/// in) plus per-format breakdowns of cards unique to each format, and
/// the source decks the data came from.
struct CommonCardsAggregation: Sendable, Equatable {
    let majorArchetypeID: String
    /// Cards present in the latest #1 deck of EVERY format the
    /// archetype exists in. The "you definitely need these" core.
    let universalCards: [CommonCardEntry]
    /// Per-format slices. Each slice's `cards` list excludes cards
    /// already in `universalCards` so the user sees only what's
    /// extra for each format.
    let perFormatCards: [PerFormatBreakdown]
    /// Distinct formats that contributed at least one deck. Used so
    /// the UI can phrase "Core (all 3 formats)" correctly even when
    /// per-format slices are empty.
    let formatsRepresented: [String]
    let sources: [AggregationSource]
    let aggregatedAt: Date
}

// MARK: - Cache file format

private struct AggregationCacheFile: Codable, Sendable {
    var entries: [String: CachedAggregation]
}

private struct CachedAggregation: Codable, Sendable {
    let aggregatedAt: Date
    let universalCards: [CommonCardEntry]
    let perFormatCards: [PerFormatBreakdown]
    let formatsRepresented: [String]
    let sources: [AggregationSource]
}

// MARK: - Protocol

protocol CommonCardsAggregatorProtocol: Sendable {
    /// Returns the most-common cards across the given archetype
    /// variants. Hits the cache when fresh, otherwise pulls from the
    /// live MTGTop8 data (latest top-1 deck per variant → decklist).
    /// `cacheKey` identifies the result for caching — typically the
    /// canonical name of an `ArchetypeGroup`.
    func aggregate(
        cacheKey: String,
        variants: [IndexedArchetype],
        forceRefresh: Bool
    ) async -> CommonCardsAggregation?

    /// Returns every cached aggregation currently on disk. Used by
    /// `SoughtAfterCardsService` to score cards across the entire
    /// browsed catalog.
    func allCachedAggregations() async -> [CommonCardsAggregation]

    /// Wipes the entire aggregation cache. Used by manual refresh.
    func clearAll() async
}

// MARK: - Implementation

/// Builds the universal + per-format common-cards breakdown for an
/// archetype group by:
///
/// 1. Fetching the latest #1 deck for each variant via
///    `LatestTopFinishesCache`.
/// 2. Fetching each unique deckID's full decklist via `DecklistCache`.
/// 3. Grouping decks by format and building per-format card sets.
/// 4. Computing the universal intersection (cards in every format).
/// 5. Returning per-format slices that EXCLUDE the universal set.
///
/// The whole pipeline takes 5-30 seconds on a cold cache (10-30
/// network requests) and is instant on a warm cache. Results are
/// persisted with a 7-day TTL in `common_cards_aggregation_v2.json`
/// (the v2 suffix invalidates older flat-list caches from before
/// the per-format refactor).
actor CommonCardsAggregator: CommonCardsAggregatorProtocol {

    static let defaultTTL: TimeInterval = 7 * 24 * 60 * 60   // 7 days
    /// Per-slice result cap so the UI doesn't render hundreds of rows.
    static let perSliceLimit = 60

    private let service: MTGTop8ServiceProtocol
    private let decklistCache: DecklistCacheProtocol
    private let cacheFile: URL
    private let ttl: TimeInterval

    private var memoryCache: AggregationCacheFile?

    init(
        service: MTGTop8ServiceProtocol = MTGTop8Service(),
        decklistCache: DecklistCacheProtocol = DecklistCache(),
        cacheDirectory: URL? = nil,
        ttl: TimeInterval = CommonCardsAggregator.defaultTTL
    ) {
        self.service = service
        self.decklistCache = decklistCache
        self.ttl = ttl

        let directory: URL
        if let cacheDirectory {
            directory = cacheDirectory
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            directory = base.appendingPathComponent("MTGCardScanner", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // v3 suffix invalidates v2 caches that were built before
        // (a) the alias-merging fix in `ArchetypeGrouper` (old caches
        //     had separate Affinity/UW Affinity/Mono Blue Affinity
        //     entries instead of one merged "Affinity" bucket) and
        // (b) the `fetchMostRecentDeck` switch in this aggregator
        //     (old caches missed Modern when no recent #1 existed,
        //     producing the "Fireblast is universal" bug).
        // Bumping the filename forces a fresh aggregation on first
        // visit; old v2 files become ~few-KB orphans.
        self.cacheFile = directory.appendingPathComponent("common_cards_aggregation_v3.json")
    }

    // MARK: - Public API

    func aggregate(
        cacheKey: String,
        variants: [IndexedArchetype],
        forceRefresh: Bool = false
    ) async -> CommonCardsAggregation? {
        loadIfNeeded()

        if !forceRefresh,
           let cached = memoryCache?.entries[cacheKey],
           !isStale(cached) {
            return cached.toAggregation(majorArchetypeID: cacheKey)
        }

        guard !variants.isEmpty else { return nil }

        // Step 1: most recent representative deck per variant.
        // We use `fetchMostRecentDeck` (any placement) instead of
        // `fetchLatestTop1` so every format the archetype exists in
        // contributes to the universal-cards intersection. With
        // `latestTop1` Modern Burn would have been excluded whenever
        // its top-20 recent finishes contained no #1, leading to
        // "Fireblast is universal" (a card illegal in Modern) — see
        // the bug report. Most-recent deck always returns *something*
        // for any format that has tournament data.
        var topDecks: [(IndexedArchetype, MTGTop8Deck)] = []
        for archetype in variants {
            if let deck = try? await service.fetchMostRecentDeck(
                archetypeID: archetype.archetypeID,
                format: archetype.format.code
            ) {
                topDecks.append((archetype, deck))
            }
        }
        guard !topDecks.isEmpty else { return nil }

        // Step 2: fetch each unique deckID's decklist, grouped by format.
        var seenDeckIDs = Set<String>()
        var sources: [AggregationSource] = []
        // formatCode → cardName → (copies, deckCount) within that format
        var perFormatCounts: [String: [String: (copies: Int, deckCount: Int)]] = [:]
        var formatNames: [String: String] = [:]

        for (archetype, deck) in topDecks {
            guard !seenDeckIDs.contains(deck.deckID) else { continue }
            seenDeckIDs.insert(deck.deckID)

            guard let decklist = await decklistCache.decklist(
                deckID: deck.deckID,
                forceRefresh: false
            ) else {
                continue
            }

            sources.append(AggregationSource(
                archetypeName: archetype.name,
                format: archetype.format.displayName,
                deckID: deck.deckID,
                player: deck.player,
                event: deck.event,
                date: deck.date
            ))

            let formatCode = archetype.format.code
            formatNames[formatCode] = archetype.format.displayName

            for entry in decklist.mainboard {
                var byCard = perFormatCounts[formatCode] ?? [:]
                var current = byCard[entry.cardName] ?? (copies: 0, deckCount: 0)
                current.copies += entry.quantity
                current.deckCount += 1
                byCard[entry.cardName] = current
                perFormatCounts[formatCode] = byCard
            }
        }

        guard !perFormatCounts.isEmpty else { return nil }

        // Step 3: universal intersection — cards present in EVERY
        // format that contributed at least one deck.
        let formatCodes = Array(perFormatCounts.keys).sorted()
        let formatCardSets: [Set<String>] = formatCodes.map { code in
            Set((perFormatCounts[code] ?? [:]).keys)
        }
        let universalNames: Set<String>
        if let first = formatCardSets.first {
            universalNames = formatCardSets.dropFirst().reduce(first) { $0.intersection($1) }
        } else {
            universalNames = []
        }

        // Build the universal entries — for each universal card, sum
        // copies and deckCount across all formats.
        let universalEntries: [CommonCardEntry] = universalNames.map { name in
            var totalCopies = 0
            var totalDeckCount = 0
            for code in formatCodes {
                if let stats = perFormatCounts[code]?[name] {
                    totalCopies += stats.copies
                    totalDeckCount += stats.deckCount
                }
            }
            return CommonCardEntry(
                cardName: name,
                totalCopies: totalCopies,
                deckCount: totalDeckCount
            )
        }
        .sorted { Self.cardSort($0, $1) }
        .prefix(Self.perSliceLimit)
        .map { $0 }

        // Step 4: per-format breakdowns — only cards NOT in universal.
        let perFormatBreakdowns: [PerFormatBreakdown] = formatCodes.compactMap { code in
            guard let byCard = perFormatCounts[code] else { return nil }
            let entries: [CommonCardEntry] = byCard
                .filter { !universalNames.contains($0.key) }
                .map { CommonCardEntry(cardName: $0.key, totalCopies: $0.value.copies, deckCount: $0.value.deckCount) }
                .sorted { Self.cardSort($0, $1) }
                .prefix(Self.perSliceLimit)
                .map { $0 }
            // Skip empty per-format sections so the UI doesn't render
            // disclosure groups with nothing inside.
            guard !entries.isEmpty else { return nil }
            return PerFormatBreakdown(
                formatCode: code,
                formatName: formatNames[code] ?? code,
                cards: entries
            )
        }

        let formatsRepresented = formatCodes.compactMap { formatNames[$0] }
        let now = Date()
        let aggregation = CommonCardsAggregation(
            majorArchetypeID: cacheKey,
            universalCards: universalEntries,
            perFormatCards: perFormatBreakdowns,
            formatsRepresented: formatsRepresented,
            sources: sources,
            aggregatedAt: now
        )

        // Persist
        var file = memoryCache ?? AggregationCacheFile(entries: [:])
        file.entries[cacheKey] = CachedAggregation(
            aggregatedAt: now,
            universalCards: universalEntries,
            perFormatCards: perFormatBreakdowns,
            formatsRepresented: formatsRepresented,
            sources: sources
        )
        memoryCache = file
        save()

        return aggregation
    }

    func allCachedAggregations() async -> [CommonCardsAggregation] {
        loadIfNeeded()
        guard let file = memoryCache else { return [] }
        return file.entries.map { key, cached in
            cached.toAggregation(majorArchetypeID: key)
        }
    }

    func clearAll() async {
        memoryCache = AggregationCacheFile(entries: [:])
        save()
    }

    // MARK: - Sorting

    /// Stable sort for ranked card lists: highest copies first, ties
    /// broken alphabetically.
    private static func cardSort(_ lhs: CommonCardEntry, _ rhs: CommonCardEntry) -> Bool {
        if lhs.totalCopies != rhs.totalCopies { return lhs.totalCopies > rhs.totalCopies }
        return lhs.cardName < rhs.cardName
    }

    // MARK: - Cache I/O

    private func loadIfNeeded() {
        if memoryCache != nil { return }
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            memoryCache = AggregationCacheFile(entries: [:])
            return
        }
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            memoryCache = try decoder.decode(AggregationCacheFile.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: cacheFile)
            memoryCache = AggregationCacheFile(entries: [:])
        }
    }

    private func save() {
        guard let memoryCache else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(memoryCache)
            try data.write(to: cacheFile, options: .atomic)
        } catch {
            // Best-effort persistence
        }
    }

    private func isStale(_ entry: CachedAggregation) -> Bool {
        Date().timeIntervalSince(entry.aggregatedAt) > ttl
    }
}

// MARK: - CachedAggregation → CommonCardsAggregation

private extension CachedAggregation {
    func toAggregation(majorArchetypeID: String) -> CommonCardsAggregation {
        CommonCardsAggregation(
            majorArchetypeID: majorArchetypeID,
            universalCards: universalCards,
            perFormatCards: perFormatCards,
            formatsRepresented: formatsRepresented,
            sources: sources,
            aggregatedAt: aggregatedAt
        )
    }
}
