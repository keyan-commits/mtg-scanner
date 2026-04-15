import Foundation

// MARK: - Models

/// One ruling for a card from Scryfall — typically a judge
/// clarification, errata, or interaction note that isn't on the card
/// itself. Surfaced in `CardDetailView` so users can read the
/// official rules guidance for a card without leaving the app.
struct CardRuling: Codable, Sendable, Identifiable, Equatable {
    /// "wotc" or "scryfall" — who published the ruling.
    let source: String
    /// ISO date string ("2023-04-14").
    let publishedAt: String
    /// The actual ruling text.
    let comment: String

    /// Synthesized stable id for SwiftUI lists.
    var id: String { "\(publishedAt)-\(comment.prefix(40))" }

    enum CodingKeys: String, CodingKey {
        case source
        case publishedAt = "published_at"
        case comment
    }
}

// MARK: - DTO

private struct ScryfallRulingsResponse: Codable, Sendable {
    let data: [CardRuling]
}

// MARK: - Errors

enum CardRulingsError: Error {
    case networkError(underlying: Error)
    case parsingError
}

// MARK: - Protocol

protocol CardRulingsServiceProtocol: Sendable {
    /// Returns the ruling list for a card by its Scryfall UUID.
    /// Cached in memory per session — rulings are static-ish so we
    /// don't need disk persistence.
    func rulings(forScryfallID id: String) async throws -> [CardRuling]
}

// MARK: - Implementation

/// Fetches and caches Scryfall card rulings. Used by `CardDetailView`
/// to populate the new "Rules & Rulings" section.
///
/// Endpoint: `https://api.scryfall.com/cards/{id}/rulings`
///
/// Cache: per-session in-memory keyed by scryfallID. Rulings change
/// rarely (only when a judge issues new clarifications) so cross-
/// session persistence isn't worth the complexity.
actor CardRulingsService: CardRulingsServiceProtocol {

    static let shared = CardRulingsService()

    private static let baseURL = "https://api.scryfall.com"
    private let httpClient: HTTPClientProtocol

    private var memoryCache: [String: [CardRuling]] = [:]

    init(httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func rulings(forScryfallID id: String) async throws -> [CardRuling] {
        if let cached = memoryCache[id] {
            return cached
        }

        guard let url = URL(string: "\(Self.baseURL)/cards/\(id)/rulings") else {
            throw CardRulingsError.parsingError
        }

        var request = URLRequest(url: url)
        request.setValue("MTGCardScanner/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            (data, _) = try await httpClient.data(for: request)
        } catch {
            throw CardRulingsError.networkError(underlying: error)
        }

        do {
            let decoded = try JSONDecoder().decode(ScryfallRulingsResponse.self, from: data)
            memoryCache[id] = decoded.data
            return decoded.data
        } catch {
            throw CardRulingsError.parsingError
        }
    }
}
