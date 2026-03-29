import Foundation

enum CardRepositoryError: Error, Equatable {
    case cardNotFound
    case networkError(URLError)
    case decodingError
}

protocol CardRepositoryProtocol: Sendable {
    func identifyCard(name: String) async throws -> Card
    func fetchCard(set: String, collectorNumber: String) async throws -> Card
    func searchCards(query: String) async throws -> [Card]
    func findAllPrintings(name: String) async throws -> [Card]
    func findVariants(name: String, setCode: String) async throws -> [Card]
}
