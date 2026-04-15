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
    /// Typo-tolerant lookup. Returns the closest-matching card by
    /// edit distance, or nil if nothing's close enough. Used as the
    /// last fallback by `CardResolver` when exact / DFC lookups fail.
    func findFuzzyMatch(name: String) async throws -> Card?

    /// Returns all basic lands in the database.
    func fetchBasicLands() async throws -> [Card]
    /// Returns all distinct sets in the database.
    func fetchAllSets() async throws -> [SetInfo]
    /// Returns all cards in a given set.
    func fetchCardsBySet(setCode: String) async throws -> [Card]
}

extension CardRepositoryProtocol {
    /// Default no-op so non-local repositories (Scryfall, mocks)
    /// don't have to implement fuzzy matching.
    func findFuzzyMatch(name: String) async throws -> Card? { nil }
    func fetchBasicLands() async throws -> [Card] { [] }
    func fetchAllSets() async throws -> [SetInfo] { [] }
    func fetchCardsBySet(setCode: String) async throws -> [Card] { [] }
}
