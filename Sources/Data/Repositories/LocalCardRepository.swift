import Foundation

// MARK: - Local Card Repository

@MainActor
final class LocalCardRepository: CardRepositoryProtocol {
    nonisolated let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - CardRepositoryProtocol

    nonisolated func identifyCard(name: String) async throws -> Card {
        guard let record = try await databaseManager.findCard(name: name) else {
            throw CardRepositoryError.cardNotFound
        }
        return record.toDomain()
    }

    nonisolated func fetchCard(set: String, collectorNumber: String) async throws -> Card {
        guard let record = try await databaseManager.findCard(setCode: set, collectorNumber: collectorNumber) else {
            throw CardRepositoryError.cardNotFound
        }
        return record.toDomain()
    }

    nonisolated func searchCards(query: String) async throws -> [Card] {
        let records = try await databaseManager.searchCards(name: query)
        return records.map { $0.toDomain() }
    }

    nonisolated func findAllPrintings(name: String) async throws -> [Card] {
        let records = try await databaseManager.findCards(name: name)
        return records.map { $0.toDomain() }
    }

    nonisolated func findVariants(name: String, setCode: String) async throws -> [Card] {
        let records = try await databaseManager.findVariants(name: name, setCode: setCode)
        return records.map { $0.toDomain() }
    }

    nonisolated func findFuzzyMatch(name: String) async throws -> Card? {
        guard let record = try await databaseManager.findFuzzyMatch(name: name) else {
            return nil
        }
        return record.toDomain()
    }

    nonisolated func fetchBasicLands() async throws -> [Card] {
        let records = try await databaseManager.fetchBasicLands()
        return records.map { $0.toDomain() }
    }

    nonisolated func fetchAllSets() async throws -> [SetInfo] {
        let tuples = try await databaseManager.fetchDistinctSets()
        return tuples.map { SetInfo(code: $0.code, name: $0.name, setType: $0.setType, iconSVGURI: nil, releasedAt: $0.releasedAt) }
    }

    nonisolated func fetchCardsBySet(setCode: String) async throws -> [Card] {
        let records = try await databaseManager.fetchCards(setCode: setCode)
        return records.map { $0.toDomain() }
    }

    nonisolated func fetchPriceMovers(limit: Int) async throws -> [Card] {
        let records = try await databaseManager.fetchPriceMovers(limit: limit)
        return records.map { $0.toDomain() }
    }
}
