import Testing
import Foundation
@testable import MTGCardScanner

@Suite("IdentifyCardUseCase Tests")
struct IdentifyCardUseCaseTests {

    // MARK: - Mock Repository

    final class MockCardRepository: CardRepositoryProtocol, @unchecked Sendable {
        var identifyCardResult: Result<Card, Error> = .failure(CardRepositoryError.cardNotFound)
        var lastIdentifyName: String?

        var fetchCardResult: Result<Card, Error> = .failure(CardRepositoryError.cardNotFound)
        var lastFetchSet: String?
        var lastFetchCollectorNumber: String?

        var searchCardsResult: Result<[Card], Error> = .failure(CardRepositoryError.cardNotFound)
        var lastSearchQuery: String?

        func identifyCard(name: String) async throws -> Card {
            lastIdentifyName = name
            return try identifyCardResult.get()
        }

        func fetchCard(set: String, collectorNumber: String) async throws -> Card {
            lastFetchSet = set
            lastFetchCollectorNumber = collectorNumber
            return try fetchCardResult.get()
        }

        func searchCards(query: String) async throws -> [Card] {
            lastSearchQuery = query
            return try searchCardsResult.get()
        }

        func findAllPrintings(name: String) async throws -> [Card] {
            return try searchCardsResult.get()
        }
    }

    // MARK: - Helpers

    static func makeCard(name: String = "Lightning Bolt") -> Card {
        Card(
            id: UUID(),
            scryfallID: "abc-123",
            name: name,
            manaCost: "{R}",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            set: SetInfo(code: "a25", name: "Masters 25", setType: "masters", iconSVGURI: nil, releasedAt: nil),
            collectorNumber: "141",
            rarity: .common,
            artist: nil,
            releasedAt: nil,
            borderColor: nil,
            frame: nil,
            illustrationID: nil,
            edhrecRank: nil,
            prices: CardPrices(usd: "1.00", usdFoil: nil, eur: nil, eurFoil: nil, tix: nil),
            legalities: FormatLegality(["modern": .legal]),
            imageURIs: [:],
            relatedPrintingsURI: nil
        )
    }

    // MARK: - Tests

    @Test("Successfully identifies a card from recognized text")
    func successfulIdentification() async throws {
        let mockRepo = MockCardRepository()
        let expectedCard = IdentifyCardUseCaseTests.makeCard(name: "Lightning Bolt")
        mockRepo.identifyCardResult = .success(expectedCard)

        let useCase = IdentifyCardUseCase(repository: mockRepo)
        let result = try await useCase.execute(recognizedText: "Lightning Bolt")

        #expect(result.name == "Lightning Bolt")
        #expect(mockRepo.lastIdentifyName == "Lightning Bolt")
    }

    @Test("Throws error when card is not found")
    func cardNotFound() async {
        let mockRepo = MockCardRepository()
        mockRepo.identifyCardResult = .failure(CardRepositoryError.cardNotFound)

        let useCase = IdentifyCardUseCase(repository: mockRepo)

        await #expect(throws: CardRepositoryError.self) {
            try await useCase.execute(recognizedText: "Nonexistent Card")
        }
    }

    @Test("Throws error on network failure")
    func networkError() async {
        let mockRepo = MockCardRepository()
        mockRepo.identifyCardResult = .failure(CardRepositoryError.networkError(URLError(.notConnectedToInternet)))

        let useCase = IdentifyCardUseCase(repository: mockRepo)

        await #expect(throws: CardRepositoryError.self) {
            try await useCase.execute(recognizedText: "Lightning Bolt")
        }
    }

    @Test("Passes recognized text directly to repository")
    func passesTextToRepository() async throws {
        let mockRepo = MockCardRepository()
        let card = IdentifyCardUseCaseTests.makeCard(name: "Black Lotus")
        mockRepo.identifyCardResult = .success(card)

        let useCase = IdentifyCardUseCase(repository: mockRepo)
        _ = try await useCase.execute(recognizedText: "  Black Lotus  ")

        #expect(mockRepo.lastIdentifyName == "  Black Lotus  ")
    }
}
