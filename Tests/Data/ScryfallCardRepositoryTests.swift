import Testing
import Foundation
@testable import MTGCardScanner

// MARK: - Mock API Client

struct MockScryfallAPIClient: ScryfallAPIClientProtocol {
    var fetchCardByNameResult: Result<ScryfallCardDTO, Error> = .failure(ScryfallError.cardNotFound)
    var fetchCardBySetResult: Result<ScryfallCardDTO, Error> = .failure(ScryfallError.cardNotFound)
    var searchCardsResult: Result<ScryfallSearchDTO, Error> = .failure(ScryfallError.cardNotFound)
    var fetchCardCollectionResult: Result<ScryfallSearchDTO, Error> = .failure(ScryfallError.cardNotFound)

    func fetchCardByName(_ name: String) async throws -> ScryfallCardDTO {
        try fetchCardByNameResult.get()
    }

    func fetchCard(set: String, collectorNumber: String) async throws -> ScryfallCardDTO {
        try fetchCardBySetResult.get()
    }

    func searchCards(query: String) async throws -> ScryfallSearchDTO {
        try searchCardsResult.get()
    }

    func fetchCardCollection(identifiers: [[String: String]]) async throws -> ScryfallSearchDTO {
        try fetchCardCollectionResult.get()
    }
}

// MARK: - Test Helpers

extension ScryfallCardRepositoryTests {
    static func makeSampleDTO() -> ScryfallCardDTO {
        ScryfallCardDTO(
            id: "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
            name: "Lightning Bolt",
            manaCost: "{R}",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            set: "2xm",
            setName: "Double Masters",
            setType: "masters",
            setURI: "https://api.scryfall.com/sets/2xm",
            collectorNumber: "117",
            rarity: "uncommon",
            artist: "Test Artist",
            borderColor: "black",
            frame: "2015",
            releasedAt: "2020-08-07",
            illustrationID: nil,
            edhrecRank: nil,
            prices: ScryfallPricesDTO(
                usd: "1.50",
                usdFoil: "3.25",
                eur: "1.10",
                eurFoil: "2.80",
                tix: "0.40"
            ),
            legalities: [
                "standard": "not_legal",
                "modern": "legal"
            ],
            imageURIs: [
                "normal": "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg"
            ],
            printsSearchURI: "https://api.scryfall.com/cards/search?q=oracleid%3Abc9b08eb"
        )
    }

    static func makeSampleSearchDTO(cards: [ScryfallCardDTO] = []) -> ScryfallSearchDTO {
        ScryfallSearchDTO(
            object: "list",
            totalCards: cards.count,
            hasMore: false,
            nextPage: nil,
            data: cards
        )
    }
}

@Suite("ScryfallCardRepository Tests")
struct ScryfallCardRepositoryTests {

    // MARK: - Fetch by Name

    @Test("identifyCard returns domain Card on success")
    func identifyCardReturnsDomainCard() async throws {
        let dto = ScryfallCardRepositoryTests.makeSampleDTO()
        var mockClient = MockScryfallAPIClient()
        mockClient.fetchCardByNameResult = .success(dto)

        let repository = ScryfallCardRepository(apiClient: mockClient)
        let card = try await repository.identifyCard(name: "Lightning Bolt")

        #expect(card.name == "Lightning Bolt")
        #expect(card.scryfallID == "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43")
        #expect(card.manaCost == "{R}")
        #expect(card.typeLine == "Instant")
        #expect(card.oracleText == "Lightning Bolt deals 3 damage to any target.")
        #expect(card.rarity == .uncommon)
    }

    @Test("identifyCard maps set info to domain")
    func identifyCardMapsSetInfo() async throws {
        let dto = ScryfallCardRepositoryTests.makeSampleDTO()
        var mockClient = MockScryfallAPIClient()
        mockClient.fetchCardByNameResult = .success(dto)

        let repository = ScryfallCardRepository(apiClient: mockClient)
        let card = try await repository.identifyCard(name: "Lightning Bolt")

        #expect(card.set.code == "2xm")
        #expect(card.set.name == "Double Masters")
        #expect(card.set.setType == "masters")
    }

    @Test("identifyCard maps prices to domain")
    func identifyCardMapsPrices() async throws {
        let dto = ScryfallCardRepositoryTests.makeSampleDTO()
        var mockClient = MockScryfallAPIClient()
        mockClient.fetchCardByNameResult = .success(dto)

        let repository = ScryfallCardRepository(apiClient: mockClient)
        let card = try await repository.identifyCard(name: "Lightning Bolt")

        #expect(card.prices.usd == "1.50")
        #expect(card.prices.usdFoil == "3.25")
        #expect(card.prices.eur == "1.10")
        #expect(card.prices.eurFoil == "2.80")
        #expect(card.prices.tix == "0.40")
    }

    @Test("identifyCard maps legalities to domain")
    func identifyCardMapsLegalities() async throws {
        let dto = ScryfallCardRepositoryTests.makeSampleDTO()
        var mockClient = MockScryfallAPIClient()
        mockClient.fetchCardByNameResult = .success(dto)

        let repository = ScryfallCardRepository(apiClient: mockClient)
        let card = try await repository.identifyCard(name: "Lightning Bolt")

        #expect(card.legalities.status(for: "modern") == .legal)
        #expect(card.legalities.status(for: "standard") == .notLegal)
    }

    @Test("identifyCard propagates cardNotFound error")
    func identifyCardPropagatesError() async {
        var mockClient = MockScryfallAPIClient()
        mockClient.fetchCardByNameResult = .failure(ScryfallError.cardNotFound)

        let repository = ScryfallCardRepository(apiClient: mockClient)

        do {
            _ = try await repository.identifyCard(name: "Nonexistent")
            Issue.record("Expected error to be thrown")
        } catch let error as ScryfallError {
            #expect(error == .cardNotFound)
        } catch {
            Issue.record("Expected ScryfallError but got \(error)")
        }
    }

    // MARK: - Fetch by Set + Collector Number

    @Test("fetchCard by set returns domain Card on success")
    func fetchCardBySetReturnsDomainCard() async throws {
        let dto = ScryfallCardRepositoryTests.makeSampleDTO()
        var mockClient = MockScryfallAPIClient()
        mockClient.fetchCardBySetResult = .success(dto)

        let repository = ScryfallCardRepository(apiClient: mockClient)
        let card = try await repository.fetchCard(set: "2xm", collectorNumber: "117")

        #expect(card.name == "Lightning Bolt")
        #expect(card.collectorNumber == "117")
    }

    // MARK: - Search

    @Test("searchCards returns array of domain Cards")
    func searchCardsReturnsDomainCards() async throws {
        let dto = ScryfallCardRepositoryTests.makeSampleDTO()
        let searchDTO = ScryfallCardRepositoryTests.makeSampleSearchDTO(cards: [dto])
        var mockClient = MockScryfallAPIClient()
        mockClient.searchCardsResult = .success(searchDTO)

        let repository = ScryfallCardRepository(apiClient: mockClient)
        let cards = try await repository.searchCards(query: "lightning bolt")

        #expect(cards.count == 1)
        #expect(cards.first?.name == "Lightning Bolt")
    }

    @Test("searchCards returns empty array for no results")
    func searchCardsReturnsEmptyArray() async throws {
        let searchDTO = ScryfallCardRepositoryTests.makeSampleSearchDTO(cards: [])
        var mockClient = MockScryfallAPIClient()
        mockClient.searchCardsResult = .success(searchDTO)

        let repository = ScryfallCardRepository(apiClient: mockClient)
        let cards = try await repository.searchCards(query: "xyznonexistent")

        #expect(cards.isEmpty)
    }

    // MARK: - Image URI Mapping

    @Test("Repository maps image URIs from DTO to domain")
    func mapsImageURIs() async throws {
        let dto = ScryfallCardRepositoryTests.makeSampleDTO()
        var mockClient = MockScryfallAPIClient()
        mockClient.fetchCardByNameResult = .success(dto)

        let repository = ScryfallCardRepository(apiClient: mockClient)
        let card = try await repository.identifyCard(name: "Lightning Bolt")

        #expect(card.imageURIs["normal"] == "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg")
    }

    // MARK: - Related Printings URI Mapping

    @Test("Repository maps prints_search_uri to relatedPrintingsURI")
    func mapsRelatedPrintingsURI() async throws {
        let dto = ScryfallCardRepositoryTests.makeSampleDTO()
        var mockClient = MockScryfallAPIClient()
        mockClient.fetchCardByNameResult = .success(dto)

        let repository = ScryfallCardRepository(apiClient: mockClient)
        let card = try await repository.identifyCard(name: "Lightning Bolt")

        #expect(card.relatedPrintingsURI == "https://api.scryfall.com/cards/search?q=oracleid%3Abc9b08eb")
    }
}
