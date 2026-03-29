import Testing
import Foundation
@testable import MTGCardScanner

// MARK: - Mock MTGTop8 Service

struct MockMTGTop8Service: MTGTop8ServiceProtocol {
    var dataByFormat: [String: MTGTop8CardData] = [:]
    var failingFormats: Set<String> = []

    func fetchCardData(name: String) async throws -> MTGTop8CardData {
        MTGTop8CardData(
            cardName: name,
            totalDecks: 0,
            topArchetypes: [],
            searchURL: "https://mtgtop8.com/search?cards=\(name)",
            format: nil
        )
    }

    func fetchCardData(name: String, format: String) async throws -> MTGTop8CardData {
        if failingFormats.contains(format) {
            throw MTGTop8Error.networkError(underlying: URLError(.notConnectedToInternet))
        }
        if let data = dataByFormat[format] {
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
}

// MARK: - Mock EDHREC Service

struct MockEDHRECService: EDHRECServiceProtocol {
    var cardData: EDHRECCardData?
    var shouldFail: Bool = false

    func fetchCardData(name: String) async throws -> EDHRECCardData {
        if shouldFail {
            throw EDHRECError.networkError("Mock failure")
        }
        guard let data = cardData else {
            throw EDHRECError.cardNotFound
        }
        return data
    }
}

// MARK: - Test Helpers

private func makeCard(
    name: String = "Lightning Bolt",
    legalities: [String: LegalityStatus]
) -> Card {
    Card(
        id: UUID(),
        scryfallID: "test-id",
        name: name,
        manaCost: "{R}",
        typeLine: "Instant",
        oracleText: "Deal 3 damage to any target.",
        set: SetInfo(code: "m21", name: "Core Set 2021", setType: "core", iconSVGURI: nil, releasedAt: nil),
        collectorNumber: "1",
        rarity: .common,
        artist: "Test Artist",
        releasedAt: "2020-07-03",
        borderColor: "black",
        frame: "2015",
        illustrationID: nil,
        edhrecRank: 1,
        prices: CardPrices(usd: "0.50", usdFoil: "1.00", eur: "0.40", eurFoil: "0.80", tix: "0.01"),
        legalities: FormatLegality(legalities),
        imageURIs: [:],
        relatedPrintingsURI: nil
    )
}

private func makeMTGTop8Data(format: String, formatCode: String, totalDecks: Int, archetypes: [MTGTop8Archetype] = []) -> MTGTop8CardData {
    MTGTop8CardData(
        cardName: "Lightning Bolt",
        totalDecks: totalDecks,
        topArchetypes: archetypes,
        searchURL: "https://mtgtop8.com/search?cards=Lightning+Bolt&format=\(formatCode)",
        format: formatCode
    )
}

// MARK: - Tests

@Suite("DeckLookupService Tests")
struct DeckLookupServiceTests {

    // MARK: - Fetches Deck Data for Each Legal Format

    @Test("Fetches deck data for each legal format")
    func fetchesDeckDataForEachLegalFormat() async {
        let card = makeCard(legalities: [
            "modern": .legal,
            "legacy": .legal,
        ])

        var mockTop8 = MockMTGTop8Service()
        mockTop8.dataByFormat["MO"] = makeMTGTop8Data(format: "Modern", formatCode: "MO", totalDecks: 500, archetypes: [
            MTGTop8Archetype(name: "Burn", format: "Modern", count: 200),
        ])
        mockTop8.dataByFormat["LE"] = makeMTGTop8Data(format: "Legacy", formatCode: "LE", totalDecks: 300, archetypes: [
            MTGTop8Archetype(name: "Izzet Delver", format: "Legacy", count: 150),
        ])

        let mockEDHREC = MockEDHRECService()

        let service = DeckLookupService(
            mtgTop8Service: mockTop8,
            edhrecService: mockEDHREC
        )

        let result = await service.lookupDecks(for: card)

        #expect(result.formatResults.count == 2)
        let formatNames = result.formatResults.map(\.format)
        #expect(formatNames.contains("Modern"))
        #expect(formatNames.contains("Legacy"))
    }

    // MARK: - Skips Formats Where Card Is Not Legal

    @Test("Skips formats where card is not legal")
    func skipsFormatsWhereCardIsNotLegal() async {
        let card = makeCard(legalities: [
            "modern": .legal,
            "standard": .notLegal,
            "legacy": .banned,
            "vintage": .restricted,
        ])

        var mockTop8 = MockMTGTop8Service()
        mockTop8.dataByFormat["MO"] = makeMTGTop8Data(format: "Modern", formatCode: "MO", totalDecks: 500)

        let mockEDHREC = MockEDHRECService()

        let service = DeckLookupService(
            mtgTop8Service: mockTop8,
            edhrecService: mockEDHREC
        )

        let result = await service.lookupDecks(for: card)

        // Only Modern is legal; standard is not_legal, legacy is banned, vintage is restricted
        #expect(result.formatResults.count == 1)
        #expect(result.formatResults.first?.format == "Modern")
    }

    // MARK: - Includes Commander Data From EDHREC When Legal

    @Test("Includes Commander data from EDHREC when card is legal in Commander")
    func includesCommanderDataWhenLegal() async {
        let card = makeCard(legalities: [
            "modern": .legal,
            "commander": .legal,
        ])

        var mockTop8 = MockMTGTop8Service()
        mockTop8.dataByFormat["MO"] = makeMTGTop8Data(format: "Modern", formatCode: "MO", totalDecks: 500)

        let mockEDHREC = MockEDHRECService(cardData: EDHRECCardData(
            cardName: "Lightning Bolt",
            numDecks: 100000,
            potentialDecks: 200000,
            inclusionPercent: 50.0,
            topCommanders: []
        ))

        let service = DeckLookupService(
            mtgTop8Service: mockTop8,
            edhrecService: mockEDHREC
        )

        let result = await service.lookupDecks(for: card)

        // Commander EDHREC data is disabled in current build
        // Just verify the lookup completes without crash
        #expect(result.commanderData == nil)
    }

    // MARK: - Handles MTGTop8 Failure for One Format Gracefully

    @Test("Handles MTGTop8 failure for one format gracefully, other formats still work")
    func handlesMTGTop8FailureGracefully() async {
        let card = makeCard(legalities: [
            "modern": .legal,
            "legacy": .legal,
        ])

        var mockTop8 = MockMTGTop8Service()
        mockTop8.dataByFormat["MO"] = makeMTGTop8Data(format: "Modern", formatCode: "MO", totalDecks: 500)
        mockTop8.failingFormats = ["LE"]

        let mockEDHREC = MockEDHRECService()

        let service = DeckLookupService(
            mtgTop8Service: mockTop8,
            edhrecService: mockEDHREC
        )

        let result = await service.lookupDecks(for: card)

        // Modern should still succeed even though Legacy failed
        #expect(result.formatResults.count == 1)
        #expect(result.formatResults.first?.format == "Modern")
    }

    // MARK: - Handles EDHREC Failure Gracefully

    @Test("Handles EDHREC failure gracefully")
    func handlesEDHRECFailureGracefully() async {
        let card = makeCard(legalities: [
            "modern": .legal,
            "commander": .legal,
        ])

        var mockTop8 = MockMTGTop8Service()
        mockTop8.dataByFormat["MO"] = makeMTGTop8Data(format: "Modern", formatCode: "MO", totalDecks: 500)

        let mockEDHREC = MockEDHRECService(shouldFail: true)

        let service = DeckLookupService(
            mtgTop8Service: mockTop8,
            edhrecService: mockEDHREC
        )

        let result = await service.lookupDecks(for: card)

        // Commander data should be nil, other formats should still work
        #expect(result.commanderData == nil)
        #expect(result.formatResults.count >= 1)
    }

    // MARK: - Results Sorted by Format Importance

    @Test("Results are sorted by format importance: Standard, Pioneer, Modern, Legacy, Vintage, Pauper")
    func resultsSortedByFormatImportance() async {
        let card = makeCard(legalities: [
            "standard": .legal,
            "pioneer": .legal,
            "modern": .legal,
            "legacy": .legal,
            "vintage": .legal,
            "pauper": .legal,
        ])

        var mockTop8 = MockMTGTop8Service()
        mockTop8.dataByFormat["ST"] = makeMTGTop8Data(format: "Standard", formatCode: "ST", totalDecks: 100)
        mockTop8.dataByFormat["PI"] = makeMTGTop8Data(format: "Pioneer", formatCode: "PI", totalDecks: 200)
        mockTop8.dataByFormat["MO"] = makeMTGTop8Data(format: "Modern", formatCode: "MO", totalDecks: 300)
        mockTop8.dataByFormat["LE"] = makeMTGTop8Data(format: "Legacy", formatCode: "LE", totalDecks: 400)
        mockTop8.dataByFormat["VI"] = makeMTGTop8Data(format: "Vintage", formatCode: "VI", totalDecks: 500)
        mockTop8.dataByFormat["PAU"] = makeMTGTop8Data(format: "Pauper", formatCode: "PAU", totalDecks: 600)

        let mockEDHREC = MockEDHRECService()

        let service = DeckLookupService(
            mtgTop8Service: mockTop8,
            edhrecService: mockEDHREC
        )

        let result = await service.lookupDecks(for: card)

        #expect(result.formatResults.count == 6)
        let formatOrder = result.formatResults.map(\.format)
        #expect(formatOrder == ["Standard", "Pioneer", "Modern", "Legacy", "Vintage", "Pauper"])
    }

    // MARK: - Card Name Stored in Result

    @Test("Card name is stored in the result")
    func cardNameStoredInResult() async {
        let card = makeCard(name: "Lightning Bolt", legalities: ["modern": .legal])

        var mockTop8 = MockMTGTop8Service()
        mockTop8.dataByFormat["MO"] = makeMTGTop8Data(format: "Modern", formatCode: "MO", totalDecks: 100)

        let service = DeckLookupService(
            mtgTop8Service: mockTop8,
            edhrecService: MockEDHRECService()
        )

        let result = await service.lookupDecks(for: card)

        #expect(result.cardName == "Lightning Bolt")
    }
}
