import Testing
import Foundation
@testable import MTGCardScanner

// MARK: - Mock MTGTop8 Service for Deck Identification

struct DeckIDMockMTGTop8Service: MTGTop8ServiceProtocol {
    /// Map of (cardName, formatCode) -> MTGTop8CardData
    var resultsByCardAndFormat: [String: MTGTop8CardData] = [:]
    var shouldFail: Bool = false

    func fetchCardData(name: String) async throws -> MTGTop8CardData {
        if shouldFail {
            throw MTGTop8Error.networkError(underlying: URLError(.notConnectedToInternet))
        }
        return MTGTop8CardData(
            cardName: name,
            totalDecks: 0,
            topArchetypes: [],
            searchURL: "https://mtgtop8.com/search?cards=\(name)",
            format: nil
        )
    }

    func fetchCardData(name: String, format: String) async throws -> MTGTop8CardData {
        if shouldFail {
            throw MTGTop8Error.networkError(underlying: URLError(.notConnectedToInternet))
        }
        let key = "\(name)|\(format)"
        if let data = resultsByCardAndFormat[key] {
            return data
        }
        return MTGTop8CardData(
            cardName: name,
            totalDecks: 0,
            topArchetypes: [],
            searchURL: "https://mtgtop8.com/search?cards=\(name)&format=\(format)",
            format: format
        )
    }

    func fetchTopDecks(archetype: String, format: String?, cardName: String?, maxPlacement: Int?) async throws -> [MTGTop8Deck] {
        []
    }

    func fetchDecksByArchetypeID(_ archetypeID: String, format: String, maxPlacement: Int?) async throws -> [MTGTop8Deck] {
        []
    }

    func fetchLatestTop1(archetypeID: String, format: String) async throws -> MTGTop8Deck? {
        nil
    }

    func fetchMostRecentDeck(archetypeID: String, format: String) async throws -> MTGTop8Deck? {
        nil
    }

    func fetchDecklist(deckID: String) async throws -> MTGTop8Decklist {
        MTGTop8Decklist(mainboard: [], sideboard: [])
    }
}

// MARK: - Test Helpers

private func makeTestCard(
    name: String,
    legalities: [String: LegalityStatus]
) -> Card {
    Card(
        scryfallID: "test-\(name)",
        name: name,
        manaCost: "{R}",
        typeLine: "Creature",
        oracleText: nil,
        set: SetInfo(code: "m21", name: "Core Set 2021", setType: "core", iconSVGURI: nil, releasedAt: nil),
        collectorNumber: "1",
        rarity: .common,
        artist: "Test Artist",
        releasedAt: "2020-07-03",
        borderColor: "black",
        frame: "2015",
        frameEffects: [],
        illustrationID: nil,
        edhrecRank: nil,
        prices: CardPrices(usd: nil, usdFoil: nil, eur: nil, eurFoil: nil, tix: nil),
        legalities: FormatLegality(legalities),
        imageURIs: [:],
        relatedPrintingsURI: nil
    )
}

private func makeArchetypeData(
    cardName: String,
    formatCode: String,
    archetypes: [(name: String, count: Int)]
) -> MTGTop8CardData {
    MTGTop8CardData(
        cardName: cardName,
        totalDecks: archetypes.reduce(0) { $0 + $1.count },
        topArchetypes: archetypes.map { MTGTop8Archetype(name: $0.name, format: formatCode, count: $0.count) },
        searchURL: "https://mtgtop8.com/search?cards=\(cardName)&format=\(formatCode)",
        format: formatCode
    )
}

// MARK: - Tests

@Suite("DeckIdentificationService Tests")
struct DeckIdentificationServiceTests {

    // MARK: - Identifies a Goblins Deck

    @Test("Identifies a Goblins deck from goblin cards")
    func identifiesGoblinsDeck() async {
        let legalities: [String: LegalityStatus] = ["modern": .legal, "legacy": .legal]

        let cards = [
            makeTestCard(name: "Goblin Guide", legalities: legalities),
            makeTestCard(name: "Goblin Piledriver", legalities: legalities),
            makeTestCard(name: "Goblin Warchief", legalities: legalities),
            makeTestCard(name: "Goblin Matron", legalities: legalities),
            makeTestCard(name: "Goblin Ringleader", legalities: legalities),
        ]

        var mock = DeckIDMockMTGTop8Service()

        // All goblin cards appear in the "Goblins" archetype
        for card in cards {
            mock.resultsByCardAndFormat["\(card.name)|LE"] = makeArchetypeData(
                cardName: card.name,
                formatCode: "LE",
                archetypes: [("Goblins", 50), ("Red Aggro", 10)]
            )
            mock.resultsByCardAndFormat["\(card.name)|MO"] = makeArchetypeData(
                cardName: card.name,
                formatCode: "MO",
                archetypes: [("Goblins", 30)]
            )
        }

        let service = DeckIdentificationService(mtgTop8Service: mock)
        let result = await service.identifyDeck(cards: cards)

        #expect(result.totalCardsAnalyzed == 5)
        #expect(!result.matches.isEmpty)

        let topMatch = result.matches.first!
        #expect(topMatch.archetype == "Goblins")
        #expect(topMatch.matchPercentage == 100.0)
        #expect(topMatch.matchedCards.count == 5)
    }

    // MARK: - Skips Basic Lands

    @Test("Skips basic lands when identifying deck")
    func skipsBasicLands() async {
        let legalities: [String: LegalityStatus] = ["modern": .legal]

        let cards = [
            makeTestCard(name: "Mountain", legalities: legalities),
            makeTestCard(name: "Mountain", legalities: legalities),
            makeTestCard(name: "Forest", legalities: legalities),
            makeTestCard(name: "Plains", legalities: legalities),
            makeTestCard(name: "Island", legalities: legalities),
            makeTestCard(name: "Swamp", legalities: legalities),
        ]

        let mock = DeckIDMockMTGTop8Service()
        let service = DeckIdentificationService(mtgTop8Service: mock)
        let result = await service.identifyDeck(cards: cards)

        #expect(result.totalCardsAnalyzed == 0)
        #expect(result.matches.isEmpty)
    }

    // MARK: - Returns Empty for No Cards

    @Test("Returns empty result for no cards")
    func returnsEmptyForNoCards() async {
        let mock = DeckIDMockMTGTop8Service()
        let service = DeckIdentificationService(mtgTop8Service: mock)
        let result = await service.identifyDeck(cards: [])

        #expect(result.totalCardsAnalyzed == 0)
        #expect(result.matches.isEmpty)
    }

    // MARK: - Handles MTGTop8 Failures Gracefully

    @Test("Handles MTGTop8 failures gracefully")
    func handlesMTGTop8FailuresGracefully() async {
        let legalities: [String: LegalityStatus] = ["modern": .legal]

        let cards = [
            makeTestCard(name: "Lightning Bolt", legalities: legalities),
            makeTestCard(name: "Goblin Guide", legalities: legalities),
        ]

        var mock = DeckIDMockMTGTop8Service()
        mock.shouldFail = true

        let service = DeckIdentificationService(mtgTop8Service: mock)
        let result = await service.identifyDeck(cards: cards)

        // Should not crash, just return no matches
        #expect(result.totalCardsAnalyzed == 2)
        #expect(result.matches.isEmpty)
    }

    // MARK: - Results Sorted by Match Percentage

    @Test("Results are sorted by match percentage descending")
    func resultsSortedByMatchPercentage() async {
        let legalities: [String: LegalityStatus] = ["legacy": .legal]

        let cards = [
            makeTestCard(name: "Lightning Bolt", legalities: legalities),
            makeTestCard(name: "Chain Lightning", legalities: legalities),
            makeTestCard(name: "Fireblast", legalities: legalities),
            makeTestCard(name: "Goblin Guide", legalities: legalities),
        ]

        var mock = DeckIDMockMTGTop8Service()

        // Burn matches 3 cards, Goblins matches 2
        for name in ["Lightning Bolt", "Chain Lightning", "Fireblast"] {
            mock.resultsByCardAndFormat["\(name)|LE"] = makeArchetypeData(
                cardName: name,
                formatCode: "LE",
                archetypes: [("Burn", 100)]
            )
        }
        // Goblin Guide also in Burn and Goblins
        mock.resultsByCardAndFormat["Goblin Guide|LE"] = makeArchetypeData(
            cardName: "Goblin Guide",
            formatCode: "LE",
            archetypes: [("Burn", 80), ("Goblins", 40)]
        )

        let service = DeckIdentificationService(mtgTop8Service: mock)
        let result = await service.identifyDeck(cards: cards)

        #expect(!result.matches.isEmpty)

        // Burn should be the top match (4 cards) above any other archetype
        let burnMatch = result.matches.first { $0.archetype == "Burn" }
        #expect(burnMatch != nil)
        #expect(burnMatch!.matchedCards.count == 4)

        // Verify descending order
        for i in 0..<(result.matches.count - 1) {
            #expect(result.matches[i].matchPercentage >= result.matches[i + 1].matchPercentage)
        }
    }
}
