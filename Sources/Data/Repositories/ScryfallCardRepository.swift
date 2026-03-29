import Foundation

// MARK: - Scryfall Card Repository

struct ScryfallCardRepository: CardRepositoryProtocol {
    private let apiClient: ScryfallAPIClientProtocol

    init(apiClient: ScryfallAPIClientProtocol = ScryfallAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: - CardRepositoryProtocol

    func identifyCard(name: String) async throws -> Card {
        let dto = try await apiClient.fetchCardByName(name)
        return dto.toDomain()
    }

    func fetchCard(set: String, collectorNumber: String) async throws -> Card {
        let dto = try await apiClient.fetchCard(set: set, collectorNumber: collectorNumber)
        return dto.toDomain()
    }

    func searchCards(query: String) async throws -> [Card] {
        let searchDTO = try await apiClient.searchCards(query: query)
        return searchDTO.data.map { $0.toDomain() }
    }

    func findAllPrintings(name: String) async throws -> [Card] {
        let searchDTO = try await apiClient.searchCards(query: "!\"\(name)\" unique:prints")
        return searchDTO.data.map { $0.toDomain() }
    }
}
