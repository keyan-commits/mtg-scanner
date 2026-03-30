import Foundation

// MARK: - Models

struct DeckMatch: Sendable, Identifiable {
    let id = UUID()
    let format: String
    let archetype: String
    let matchedCards: [String]
    let matchPercentage: Double
    let totalDecks: Int
}

struct DeckIdentificationResult: Sendable {
    let matches: [DeckMatch]
    let totalCardsAnalyzed: Int
}

// MARK: - Protocol

protocol DeckIdentificationServiceProtocol: Sendable {
    func identifyDeck(cards: [Card]) async -> DeckIdentificationResult
}

// MARK: - Implementation

struct DeckIdentificationService: DeckIdentificationServiceProtocol, @unchecked Sendable {
    private let mtgTop8Service: MTGTop8ServiceProtocol

    /// Format display names mapped to MTGTop8 codes, in importance order.
    private static let formatMappings: [(name: String, code: String, key: String)] = [
        ("Standard", "ST", "standard"),
        ("Pioneer", "PI", "pioneer"),
        ("Modern", "MO", "modern"),
        ("Legacy", "LE", "legacy"),
        ("Vintage", "VI", "vintage"),
        ("Pauper", "PAU", "pauper"),
        ("Premodern", "PREM", "premodern"),
    ]

    private static let basicLands: Set<String> = [
        "Plains", "Island", "Swamp", "Mountain", "Forest",
    ]

    init(mtgTop8Service: MTGTop8ServiceProtocol) {
        self.mtgTop8Service = mtgTop8Service
    }

    func identifyDeck(cards: [Card]) async -> DeckIdentificationResult {
        // 1. Deduplicate and filter out basic lands
        let uniqueNames = Set(cards.map(\.name)).subtracting(Self.basicLands)
        guard !uniqueNames.isEmpty else {
            return DeckIdentificationResult(matches: [], totalCardsAnalyzed: 0)
        }

        // 2. Determine which formats the majority of cards are legal in
        let relevantFormats = determineRelevantFormats(cards: cards)
        guard !relevantFormats.isEmpty else {
            return DeckIdentificationResult(matches: [], totalCardsAnalyzed: uniqueNames.count)
        }

        // 3. Fetch archetype data for each card (up to 15 most distinctive)
        let cardNames = Array(uniqueNames.prefix(15))
        let cardDataMap = await fetchCardData(cardNames: cardNames, formats: relevantFormats)

        // 4. Build voting map per format and score
        var allMatches: [DeckMatch] = []

        for format in relevantFormats {
            let formatMatches = buildFormatMatches(
                format: format,
                cardNames: cardNames,
                cardDataMap: cardDataMap,
                totalUniqueCards: uniqueNames.count
            )
            allMatches.append(contentsOf: formatMatches)
        }

        // 5. Sort by match percentage descending
        let sorted = allMatches.sorted { $0.matchPercentage > $1.matchPercentage }

        return DeckIdentificationResult(
            matches: sorted,
            totalCardsAnalyzed: uniqueNames.count
        )
    }

    // MARK: - Private Helpers

    /// Determines which formats most cards are legal in.
    private func determineRelevantFormats(
        cards: [Card]
    ) -> [(name: String, code: String, key: String)] {
        let uniqueCards = Dictionary(grouping: cards, by: \.name).values.compactMap(\.first)
        let totalCards = uniqueCards.count

        return Self.formatMappings.filter { mapping in
            let legalCount = uniqueCards.filter { card in
                card.legalities.status(for: mapping.key) == .legal
            }.count
            // Include format if at least half the cards are legal
            return legalCount > totalCards / 2
        }
    }

    /// Fetches MTGTop8 data for each card in each format, with caching.
    private func fetchCardData(
        cardNames: [String],
        formats: [(name: String, code: String, key: String)]
    ) async -> [String: [String: MTGTop8CardData]] {
        // Key: cardName -> formatCode -> data
        typealias CardFormatData = (card: String, format: String, data: MTGTop8CardData)

        let results: [CardFormatData] = await withTaskGroup(
            of: CardFormatData?.self,
            returning: [CardFormatData].self
        ) { group in
            for cardName in cardNames {
                for format in formats {
                    group.addTask {
                        do {
                            let data = try await mtgTop8Service.fetchCardData(
                                name: cardName, format: format.code
                            )
                            return (card: cardName, format: format.code, data: data)
                        } catch {
                            return nil
                        }
                    }
                }
            }

            var collected: [CardFormatData] = []
            for await result in group {
                if let result {
                    collected.append(result)
                }
            }
            return collected
        }

        // Organize into nested dictionary
        var map: [String: [String: MTGTop8CardData]] = [:]
        for result in results {
            map[result.card, default: [:]][result.format] = result.data
        }
        return map
    }

    /// Builds deck matches for a single format by voting across card archetypes.
    private func buildFormatMatches(
        format: (name: String, code: String, key: String),
        cardNames: [String],
        cardDataMap: [String: [String: MTGTop8CardData]],
        totalUniqueCards: Int
    ) -> [DeckMatch] {
        // Voting map: archetype name -> set of card names that appear in it
        var archetypeVotes: [String: Set<String>] = [:]
        var archetypeTotalDecks: [String: Int] = [:]

        for cardName in cardNames {
            guard let formatData = cardDataMap[cardName]?[format.code] else { continue }

            for archetype in formatData.topArchetypes {
                archetypeVotes[archetype.name, default: []].insert(cardName)
                // Use the max count seen across cards for this archetype
                let existing = archetypeTotalDecks[archetype.name] ?? 0
                archetypeTotalDecks[archetype.name] = max(existing, archetype.count)
            }
        }

        // Skip archetypes that appear for nearly every card (too generic)
        let filteredArchetypes = archetypeVotes.filter { _, matchedCards in
            matchedCards.count >= 2
        }

        // Score and create matches
        let matches = filteredArchetypes.map { archetype, matchedCards -> DeckMatch in
            let percentage = Double(matchedCards.count) / Double(totalUniqueCards) * 100.0
            return DeckMatch(
                format: format.name,
                archetype: archetype,
                matchedCards: matchedCards.sorted(),
                matchPercentage: percentage,
                totalDecks: archetypeTotalDecks[archetype] ?? 0
            )
        }

        // Return top 5 sorted by match percentage
        return Array(matches.sorted { $0.matchPercentage > $1.matchPercentage }.prefix(5))
    }
}
