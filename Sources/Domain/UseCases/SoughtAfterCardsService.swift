import Foundation

// MARK: - Result type

/// One row in the home page's "Top sought-after cards" section. Holds
/// the scoring breakdown so the UI can show "in N archetypes"
/// subtitles without recomputing.
struct SoughtAfterCard: Sendable, Identifiable, Equatable {
    let cardName: String
    /// Number of distinct major archetypes (canonical groups) that
    /// have this card in their aggregated card lists.
    let archetypeCount: Int
    /// Total copies summed across every cached aggregation. Used as
    /// the secondary tiebreaker.
    let totalCopies: Int

    var id: String { cardName }
}

/// Status surfaced to the home view while the global ranking warms up.
enum SoughtAfterStatus: Sendable, Equatable {
    /// Cache is empty, no warm-up has started yet.
    case idle
    /// Background warm-up is running. `(loaded, total)` reports progress.
    case warming(loaded: Int, total: Int)
    /// At least one archetype is in the cache; cards are usable.
    case ready(cards: [SoughtAfterCard])
}

/// One section of the dedicated "Most Sought-After Cards" detail
/// screen — typically one per MTGTop8 format plus an "Overall" entry.
struct FormatTopCards: Sendable, Identifiable, Equatable {
    /// `nil` for the "Overall" section, otherwise the MTGTop8 format
    /// code (e.g. "MO", "ST", "LE").
    let formatCode: String?
    /// Display name shown in the section header.
    let formatName: String
    let cards: [SoughtAfterCard]

    var id: String { formatCode ?? "overall" }
}

// MARK: - Service

protocol SoughtAfterCardsServiceProtocol: Sendable {
    /// Returns the top N most sought-after cards, ranked across the
    /// entire aggregation cache. Filters to cards appearing in at
    /// least 2 distinct archetypes so a single browsed deck can't
    /// dominate the list.
    func topCards(limit: Int) async -> [SoughtAfterCard]

    /// Returns one section of top-N cards per format that has any
    /// data in the cache, plus an "Overall" section. Used by the
    /// dedicated `SoughtAfterCardsScreen` accessible from the home
    /// section header.
    func topCardsByFormat(limit: Int) async -> [FormatTopCards]
}

/// Computes the home page's "Top 10 Most Sought-After Cards" by
/// walking every cached `CommonCardsAggregation` and ranking cards by:
///
/// 1. **Distinct archetype count** — how many different major
///    archetypes use this card. The most universally-applicable
///    cards rise to the top.
/// 2. **Total copies** — secondary tiebreaker. A 4-of in many decks
///    beats a 1-of in many decks.
/// 3. **Alphabetical** — final stable sort.
///
/// **Single-archetype filter**: cards appearing in only one cached
/// archetype are excluded entirely. This prevents a freshly-browsed
/// deck (e.g., Affinity) from spamming the home list with its
/// archetype-specific staples (Great Furnace, Seat of the Synod, Myr
/// Enforcer). Once at least 2 archetypes are warmed, the list shows
/// genuine cross-archetype chase cards.
///
/// **Pre-warming**: `prewarmCuratedMajors` runs the aggregator over
/// every entry in `MajorArchetypes.all` (~12 hand-picked archetypes
/// covering every major format). This populates the cache with
/// "global-ish" data so the home list is meaningful from first launch
/// instead of waiting for the user to manually browse archetypes.
struct SoughtAfterCardsService: SoughtAfterCardsServiceProtocol {

    /// Cards must appear in at least this many distinct archetypes
    /// to be included. Prevents single-archetype spam.
    static let minArchetypeCount = 2

    /// Card names that are excluded from the sought-after ranking
    /// because they're trivially universal — every deck runs basics,
    /// so they'd otherwise dominate the list with archetype counts
    /// equal to the number of cached archetypes. The user wants
    /// "what's actually expensive / contested", not "Plains."
    static let excludedNames: Set<String> = [
        "Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes",
        "Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp",
        "Snow-Covered Mountain", "Snow-Covered Forest",
    ]

    private let aggregator: CommonCardsAggregatorProtocol
    private let archetypeIndex: MTGTop8ArchetypeIndexProtocol

    init(
        aggregator: CommonCardsAggregatorProtocol = CommonCardsAggregator(),
        archetypeIndex: MTGTop8ArchetypeIndexProtocol = MTGTop8ArchetypeIndex()
    ) {
        self.aggregator = aggregator
        self.archetypeIndex = archetypeIndex
    }

    // MARK: - Public API

    func topCards(limit: Int = 10) async -> [SoughtAfterCard] {
        let aggregations = await aggregator.allCachedAggregations()
        guard !aggregations.isEmpty else { return [] }

        var byCard: [String: (archetypes: Set<String>, copies: Int)] = [:]

        for aggregation in aggregations {
            let entries = aggregation.universalCards
                + aggregation.perFormatCards.flatMap { $0.cards }
            for entry in entries {
                // Drop basic lands and other trivially-universal
                // names BEFORE accumulation so they never pollute the
                // ranking even if they hit the archetype-count floor.
                if Self.excludedNames.contains(entry.cardName) { continue }
                var current = byCard[entry.cardName] ?? (archetypes: Set<String>(), copies: 0)
                current.archetypes.insert(aggregation.majorArchetypeID)
                current.copies += entry.totalCopies
                byCard[entry.cardName] = current
            }
        }

        return byCard
            .filter { $0.value.archetypes.count >= Self.minArchetypeCount }
            .map { name, stats in
                SoughtAfterCard(
                    cardName: name,
                    archetypeCount: stats.archetypes.count,
                    totalCopies: stats.copies
                )
            }
            .sorted { lhs, rhs in
                if lhs.archetypeCount != rhs.archetypeCount {
                    return lhs.archetypeCount > rhs.archetypeCount
                }
                if lhs.totalCopies != rhs.totalCopies {
                    return lhs.totalCopies > rhs.totalCopies
                }
                return lhs.cardName < rhs.cardName
            }
            .prefix(limit)
            .map { $0 }
    }

    func topCardsByFormat(limit: Int = 10) async -> [FormatTopCards] {
        let aggregations = await aggregator.allCachedAggregations()
        guard !aggregations.isEmpty else { return [] }

        // Build the Overall list using the existing top-cards logic
        // (filtered + ranked + truncated).
        let overall = await topCards(limit: limit)
        var sections: [FormatTopCards] = [
            FormatTopCards(formatCode: nil, formatName: "Overall", cards: overall)
        ]

        // Per-format breakdown: for each format that contributed to
        // any cached aggregation, accumulate cards as
        //   universalCards (apply to every format the aggregation
        //   covered) + that format's perFormatCards slice.
        var byFormat: [String: (name: String, cards: [String: (archetypes: Set<String>, copies: Int)])] = [:]

        for aggregation in aggregations {
            // Format codes that contributed to this aggregation. Take
            // them from perFormatCards (already coded) and from the
            // sources list (display names → reverse to codes).
            var contributingCodes = Set(aggregation.perFormatCards.map(\.formatCode))
            for source in aggregation.sources {
                if let format = MTGTop8Format.fromDisplayName(source.format) {
                    contributingCodes.insert(format.code)
                }
            }

            // Universal cards apply to every contributing format.
            for code in contributingCodes {
                let displayName = MTGTop8Format(rawValue: code)?.displayName ?? code
                var bucket = byFormat[code] ?? (name: displayName, cards: [:])
                bucket.name = displayName
                for entry in aggregation.universalCards {
                    if Self.excludedNames.contains(entry.cardName) { continue }
                    var current = bucket.cards[entry.cardName] ?? (archetypes: Set<String>(), copies: 0)
                    current.archetypes.insert(aggregation.majorArchetypeID)
                    current.copies += entry.totalCopies
                    bucket.cards[entry.cardName] = current
                }
                byFormat[code] = bucket
            }

            // Per-format slices count only for their own format.
            for slice in aggregation.perFormatCards {
                let displayName = MTGTop8Format(rawValue: slice.formatCode)?.displayName ?? slice.formatName
                var bucket = byFormat[slice.formatCode] ?? (name: displayName, cards: [:])
                bucket.name = displayName
                for entry in slice.cards {
                    if Self.excludedNames.contains(entry.cardName) { continue }
                    var current = bucket.cards[entry.cardName] ?? (archetypes: Set<String>(), copies: 0)
                    current.archetypes.insert(aggregation.majorArchetypeID)
                    current.copies += entry.totalCopies
                    bucket.cards[entry.cardName] = current
                }
                byFormat[slice.formatCode] = bucket
            }
        }

        // For each format bucket, rank + truncate. We DON'T apply
        // the >=2-archetype filter here because per-format the data
        // is much sparser — most cards appear in only one archetype
        // per format, and filtering them out would empty the list.
        // Basics are still excluded above.
        for (code, bucket) in byFormat {
            let ranked = bucket.cards
                .map { name, stats in
                    SoughtAfterCard(
                        cardName: name,
                        archetypeCount: stats.archetypes.count,
                        totalCopies: stats.copies
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.archetypeCount != rhs.archetypeCount {
                        return lhs.archetypeCount > rhs.archetypeCount
                    }
                    if lhs.totalCopies != rhs.totalCopies {
                        return lhs.totalCopies > rhs.totalCopies
                    }
                    return lhs.cardName < rhs.cardName
                }
                .prefix(limit)
                .map { $0 }
            sections.append(FormatTopCards(
                formatCode: code,
                formatName: bucket.name,
                cards: ranked
            ))
        }

        // Stable order: Overall first, then formats by
        // MTGTop8Format.allCases ordering (Standard, Pioneer, ...).
        let formatPriority: [String: Int] = Dictionary(
            uniqueKeysWithValues: MTGTop8Format.allCases.enumerated().map { ($0.element.code, $0.offset) }
        )
        return sections.sorted { lhs, rhs in
            if lhs.formatCode == nil { return true }
            if rhs.formatCode == nil { return false }
            let lp = formatPriority[lhs.formatCode ?? ""] ?? .max
            let rp = formatPriority[rhs.formatCode ?? ""] ?? .max
            return lp < rp
        }
    }

    /// Pre-aggregates every curated major archetype so the home page
    /// has meaningful global data without requiring the user to
    /// manually browse archetypes first.
    ///
    /// `progress` is invoked on the main actor after each major
    /// completes so the home view can update its progress UI.
    /// Returns once every major has been aggregated (or skipped
    /// because it's already cached and fresh).
    @MainActor
    func prewarmCuratedMajors(
        progress: @escaping @MainActor (_ loaded: Int, _ total: Int) -> Void
    ) async {
        let curated = MajorArchetypes.all
        let total = curated.count
        progress(0, total)

        // Load the full archetype catalog once so we can find each
        // major's variants without re-scraping per major.
        guard let allArchetypes = try? await archetypeIndex.archetypes(forceRefresh: false) else {
            return
        }
        let groups = ArchetypeGrouper.group(archetypes: allArchetypes)

        var loaded = 0
        for major in curated {
            // Find the group whose canonical bucket matches this
            // curated major (the grouper aliases by matchTerms so
            // "burn" + "red deck wins" + "sligh" all bucket under
            // major.id == "burn").
            if let group = groups.first(where: { $0.canonicalName == major.id }) {
                _ = await aggregator.aggregate(
                    cacheKey: group.canonicalName,
                    variants: group.variants,
                    forceRefresh: false
                )
            }
            loaded += 1
            progress(loaded, total)
        }
    }

    /// True if at least `Self.minArchetypeCount` archetypes are
    /// already in the aggregation cache. Used by the home view to
    /// skip the pre-warm UI when the cache is already useful.
    func hasUsefulCache() async -> Bool {
        let aggregations = await aggregator.allCachedAggregations()
        return aggregations.count >= Self.minArchetypeCount
    }

    // MARK: - Auto-populate from staples

    private static let lastRefreshKey = "soughtAfterLastRefresh"

    /// Whether it's been >24h since the last prewarm refresh.
    var needsDailyRefresh: Bool {
        let last = UserDefaults.standard.double(forKey: Self.lastRefreshKey)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last > 24 * 60 * 60
    }

    /// Records that a refresh just completed.
    func markRefreshed() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastRefreshKey)
    }

    /// Builds seed data from hardcoded format staple lists.
    /// Used when the aggregation cache is empty so the home screen
    /// shows useful data immediately without waiting for MTGTop8.
    func seedFromStaples() -> [SoughtAfterCard] {
        // Collect all card names across all format staple lists
        var cardCounts: [String: Int] = [:]
        let allStapleLists: [[LandCategory]] = [
            ModernStaples.all, LegacyStaples.all, PioneerStaples.all,
            VintageStaples.all, PauperStaples.all, PremodernStaples.all,
            CEDHStaples.all
        ]
        for list in allStapleLists {
            for category in list {
                for name in category.cardNames {
                    cardCounts[name, default: 0] += 1
                }
            }
        }

        // Cards that appear in multiple formats are the most sought-after
        return cardCounts
            .map { SoughtAfterCard(cardName: $0.key, archetypeCount: $0.value, totalCopies: $0.value) }
            .sorted { ($0.archetypeCount, $0.totalCopies, $0.cardName) > ($1.archetypeCount, $1.totalCopies, $1.cardName) }
    }
}
