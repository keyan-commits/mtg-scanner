import Foundation

/// One suggested card the user might want to add to an undersized deck.
struct DeckSuggestion: Identifiable, Sendable {
    let id = UUID()
    let cardName: String
    /// How many tournament decks (out of `totalDecksScanned`) included this card.
    let frequency: Int
    /// Average quantity per deck (so 4-of's stand out from 1-of's).
    let averageQuantity: Double
    /// Total decks we scanned to compute this — denominator for `frequency`.
    let totalDecksScanned: Int
    /// Number of copies the canonical archetype recommends for this card,
    /// if the suggestion came from a `ClassicArchetype` match. Nil for
    /// MTGTop8-derived suggestions.
    let recommendedQuantity: Int?

    var frequencyPercent: Int {
        guard totalDecksScanned > 0 else { return 0 }
        return Int(round(Double(frequency) / Double(totalDecksScanned) * 100))
    }
}

/// Bundles the suggestion list with optional metadata about *where* the
/// suggestions came from. The UI uses this to label the section
/// (e.g. "From: Necropotence Black 1996") instead of always showing the
/// generic "from tournament decks."
struct DeckSuggestionResult {
    let suggestions: [DeckSuggestion]
    /// Set when the suggestions came from a hand-curated classic archetype.
    let archetypeMatch: ArchetypeMatch?

    static let empty = DeckSuggestionResult(suggestions: [], archetypeMatch: nil)
}

/// Looks at recent tournament decks for the deck's format that share cards
/// with the user's deck, then aggregates the most common cards across those
/// matches and recommends ones the user is missing.
///
/// Strategy:
/// 1. Pick 2-3 "signature" cards from the user's deck (ignoring basic lands).
/// 2. For each, ask MTGTop8 for tournament decks in the deck's format
///    that play that card.
/// 3. Fetch each matched decklist's mainboard.
/// 4. Aggregate card frequency across all matched decks.
/// 5. Filter out cards the user already has.
/// 6. Return the top N suggestions sorted by frequency × average qty.
@MainActor
final class DeckSuggestionService {

    private let mtgTop8Service: MTGTop8ServiceProtocol
    /// Cap on how many tournament decklists we'll fetch per suggestion request.
    /// Each one is an HTTP call so this is the rate-limit knob.
    private let maxDecklistsToScan: Int

    init(mtgTop8Service: MTGTop8ServiceProtocol, maxDecklistsToScan: Int = 8) {
        self.mtgTop8Service = mtgTop8Service
        self.maxDecklistsToScan = maxDecklistsToScan
    }

    /// Returns up to `limit` suggested cards for the deck. Returns an empty
    /// result on any failure (network, parsing, etc.) — suggestions are
    /// non-essential and shouldn't crash the screen.
    ///
    /// Strategy:
    /// 1. Try matching the user's deck against the curated `ClassicArchetypes`
    ///    database. If it matches above 50%, return the missing cards from
    ///    that canonical list — these are higher quality than scraped data
    ///    and work for vintage / pre-2003 decks where MTGTop8 has nothing.
    /// 2. Fall back to MTGTop8 scraping for everything else.
    func suggestions(
        forDeckCards existing: [String],
        format: String,
        limit: Int = 12
    ) async -> DeckSuggestionResult {
        // 1. Try the curated archetype database first.
        if let match = ArchetypeMatcher.bestMatch(for: existing, minThreshold: 0.5) {
            let archetypeSuggestions = match.missing.prefix(limit).map { entry in
                DeckSuggestion(
                    cardName: entry.cardName,
                    frequency: 1,
                    averageQuantity: Double(entry.quantity),
                    totalDecksScanned: 1,
                    recommendedQuantity: entry.quantity
                )
            }
            return DeckSuggestionResult(
                suggestions: Array(archetypeSuggestions),
                archetypeMatch: match
            )
        }

        // 2. Fall back to MTGTop8 scraping.
        let scraped = await fetchFromMTGTop8(existing: existing, format: format, limit: limit)
        return DeckSuggestionResult(suggestions: scraped, archetypeMatch: nil)
    }

    /// MTGTop8-based suggestion path. Used when the curated archetype
    /// database doesn't match. This is the original implementation, just
    /// extracted into its own method.
    private func fetchFromMTGTop8(
        existing: [String],
        format: String,
        limit: Int
    ) async -> [DeckSuggestion] {
        let existingNames = Set(existing.map { $0.lowercased() })

        // Pick 3 signature cards (not basic lands) to anchor the search.
        // Dedupe by name first so 4 copies of "Dark Ritual" don't all become
        // "the same signature card." Prefer cards with the highest count in
        // the user's deck (4-of's are typically archetype-defining).
        let basics: Set<String> = ["plains", "island", "swamp", "mountain", "forest", "wastes"]
        var counts: [String: (display: String, count: Int)] = [:]
        for name in existing {
            let key = name.lowercased()
            if basics.contains(key) { continue }
            if var entry = counts[key] {
                entry.count += 1
                counts[key] = entry
            } else {
                counts[key] = (display: name, count: 1)
            }
        }
        let signatureCards = counts.values
            .sorted { $0.count > $1.count || ($0.count == $1.count && $0.display < $1.display) }
            .prefix(3)
            .map { $0.display }

        guard !signatureCards.isEmpty else { return [] }

        // Collect candidate tournament decks — fetch in parallel.
        let candidateDecks: [MTGTop8Deck] = await withTaskGroup(of: [MTGTop8Deck].self) { group in
            for card in signatureCards {
                group.addTask { [mtgTop8Service] in
                    (try? await mtgTop8Service.fetchTopDecks(
                        archetype: "",
                        format: format,
                        cardName: card
                    )) ?? []
                }
            }
            var combined: [MTGTop8Deck] = []
            for await batch in group {
                combined.append(contentsOf: batch)
            }
            return combined
        }

        // Dedupe by deckID and cap to the rate-limit budget
        var seen: Set<String> = []
        let uniqueDecks = candidateDecks.filter { deck in
            guard !seen.contains(deck.deckID) else { return false }
            seen.insert(deck.deckID)
            return true
        }
        let toScan = Array(uniqueDecks.prefix(maxDecklistsToScan))
        guard !toScan.isEmpty else { return [] }

        // Fetch each decklist's mainboard — also in parallel. This is the
        // hottest part of the request budget; running these sequentially
        // would mean ~8 round-trips on the wire.
        let perDeckMainboards: [[MTGTop8DecklistEntry]] = await withTaskGroup(of: [MTGTop8DecklistEntry]?.self) { group in
            for deck in toScan {
                group.addTask { [mtgTop8Service] in
                    (try? await mtgTop8Service.fetchDecklist(deckID: deck.deckID))?.mainboard
                }
            }
            var collected: [[MTGTop8DecklistEntry]] = []
            for await result in group {
                if let mainboard = result {
                    collected.append(mainboard)
                }
            }
            return collected
        }
        let decksFetched = perDeckMainboards.count
        guard decksFetched > 0 else { return [] }
        let allEntries = perDeckMainboards.flatMap { $0 }

        // Aggregate: per card, how many decks include it + average qty.
        // Now that we have per-deck arrays, the dedup is exact (no heuristic).
        struct Aggregate {
            var deckCount: Int = 0
            var totalQty: Int = 0
        }
        var byCard: [String: Aggregate] = [:]
        for mainboard in perDeckMainboards {
            var seenInDeck: Set<String> = []
            for entry in mainboard {
                let key = entry.cardName.lowercased()
                byCard[key, default: Aggregate()].totalQty += entry.quantity
                if !seenInDeck.contains(key) {
                    seenInDeck.insert(key)
                    byCard[key]!.deckCount += 1
                }
            }
        }

        // Build suggestions, excluding cards already in the user's deck and
        // basic lands (the user can pick those manually).
        let suggestions = byCard
            .compactMap { (key, agg) -> DeckSuggestion? in
                if existingNames.contains(key) { return nil }
                if basics.contains(key) { return nil }
                guard agg.deckCount > 0 else { return nil }
                let avgQty = Double(agg.totalQty) / Double(agg.deckCount)
                // Use original casing from the entries
                let displayName = allEntries.first { $0.cardName.lowercased() == key }?.cardName ?? key
                return DeckSuggestion(
                    cardName: displayName,
                    frequency: agg.deckCount,
                    averageQuantity: avgQty,
                    totalDecksScanned: decksFetched,
                    recommendedQuantity: nil
                )
            }
            // Rank by frequency × average qty (so 4-of's beat 1-of's at the same frequency)
            .sorted { lhs, rhs in
                let lhsScore = Double(lhs.frequency) * lhs.averageQuantity
                let rhsScore = Double(rhs.frequency) * rhs.averageQuantity
                return lhsScore > rhsScore
            }
            .prefix(limit)

        return Array(suggestions)
    }
}
