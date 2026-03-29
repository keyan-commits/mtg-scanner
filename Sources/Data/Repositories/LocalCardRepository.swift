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
}
