import Foundation

/// Result of matching a user's deck against the curated `ClassicArchetypes` database.
struct ArchetypeMatch {
    let archetype: ClassicArchetype
    /// 0.0–1.0. How much of the canonical archetype is present in the
    /// user's deck. Computed as `sum(min(userQty, canonQty)) / sum(canonQty)`.
    let similarity: Double
    /// Cards the canonical version has that the user is missing or short on.
    /// Each entry's `quantity` is the *missing* amount, not the total.
    let missing: [(cardName: String, quantity: Int)]

    var similarityPercent: Int {
        Int(round(similarity * 100))
    }
}

/// Matches a user's deck against the hand-curated `ClassicArchetypes` database.
/// Returns the best match if its similarity score is above `minThreshold`,
/// nil otherwise. Used by `DeckSuggestionService` as a higher-quality
/// alternative to MTGTop8 scraping for vintage / pre-2003 decks.
enum ArchetypeMatcher {

    static func bestMatch(
        for deckCards: [String],
        minThreshold: Double = 0.5
    ) -> ArchetypeMatch? {
        // Build a count map of the user's deck.
        var userCounts: [String: Int] = [:]
        for name in deckCards {
            userCounts[name.lowercased(), default: 0] += 1
        }

        var best: ArchetypeMatch?
        for archetype in ClassicArchetypes.all {
            let match = score(archetype: archetype, against: userCounts)
            if match.similarity >= minThreshold {
                if best == nil || match.similarity > best!.similarity {
                    best = match
                }
            }
        }
        return best
    }

    private static func score(
        archetype: ClassicArchetype,
        against userCounts: [String: Int]
    ) -> ArchetypeMatch {
        // Sum-of-mins similarity: how much of the canonical deck the user
        // already has.
        var matchedQty = 0
        var canonicalTotal = 0
        var missing: [(cardName: String, quantity: Int)] = []

        for (cardName, canonQty) in archetype.mainboard {
            canonicalTotal += canonQty
            let userQty = userCounts[cardName.lowercased(), default: 0]
            let overlap = min(userQty, canonQty)
            matchedQty += overlap
            let short = canonQty - overlap
            if short > 0 {
                missing.append((cardName: cardName, quantity: short))
            }
        }

        let similarity = canonicalTotal > 0 ? Double(matchedQty) / Double(canonicalTotal) : 0
        // Sort missing cards by quantity desc so the biggest gaps come first.
        missing.sort { $0.quantity > $1.quantity }

        return ArchetypeMatch(
            archetype: archetype,
            similarity: similarity,
            missing: missing
        )
    }
}
