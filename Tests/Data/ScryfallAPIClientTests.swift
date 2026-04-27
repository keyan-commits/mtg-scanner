import Testing
import Foundation
@testable import MTGCardScanner

// MARK: - Mock HTTP Client

struct MockHTTPClient: HTTPClientProtocol {
    var result: Result<(Data, URLResponse), Error>

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try result.get()
    }
}

extension MockHTTPClient {
    static func success(data: Data, statusCode: Int = 200, url: URL? = nil) -> MockHTTPClient {
        let response = HTTPURLResponse(
            url: url ?? URL(string: "https://api.scryfall.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return MockHTTPClient(result: .success((data, response)))
    }

    static func failure(_ error: Error) -> MockHTTPClient {
        MockHTTPClient(result: .failure(error))
    }
}

@Suite("ScryfallAPIClient Tests")
struct ScryfallAPIClientTests {

    // MARK: - Test Fixtures

    static let singleCardJSON = """
    {
        "id": "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
        "name": "Lightning Bolt",
        "mana_cost": "{R}",
        "type_line": "Instant",
        "oracle_text": "Lightning Bolt deals 3 damage to any target.",
        "set": "2xm",
        "set_name": "Double Masters",
        "set_type": "masters",
        "set_uri": "https://api.scryfall.com/sets/2xm",
        "collector_number": "117",
        "rarity": "uncommon",
        "prices": { "usd": "1.50" },
        "legalities": { "modern": "legal" },
        "image_uris": { "normal": "https://example.com/bolt.jpg" }
    }
    """.data(using: .utf8)!

    static let searchResultJSON = """
    {
        "object": "list",
        "total_cards": 1,
        "has_more": false,
        "data": [
            {
                "id": "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
                "name": "Lightning Bolt",
                "type_line": "Instant",
                "set": "2xm",
                "set_name": "Double Masters",
                "set_type": "masters",
                "set_uri": "https://api.scryfall.com/sets/2xm",
                "collector_number": "117",
                "rarity": "uncommon",
                "prices": {},
                "legalities": {},
                "image_uris": {}
            }
        ]
    }
    """.data(using: .utf8)!

    static let notFoundJSON = """
    {
        "object": "error",
        "code": "not_found",
        "status": 404,
        "details": "No card found"
    }
    """.data(using: .utf8)!

    static let malformedJSON = "{ not valid json }".data(using: .utf8)!

    // MARK: - Successful Card Lookup

    @Test("fetchCardByName returns decoded card on success")
    func fetchCardByNameSuccess() async throws {
        let httpClient = MockHTTPClient.success(data: ScryfallAPIClientTests.singleCardJSON)
        let client = ScryfallAPIClient(httpClient: httpClient)

        let card = try await client.fetchCardByName("Lightning Bolt")

        #expect(card.name == "Lightning Bolt")
        #expect(card.set == "2xm")
        #expect(card.collectorNumber == "117")
    }

    @Test("fetchCard by set and collector number returns decoded card")
    func fetchCardBySetSuccess() async throws {
        let httpClient = MockHTTPClient.success(data: ScryfallAPIClientTests.singleCardJSON)
        let client = ScryfallAPIClient(httpClient: httpClient)

        let card = try await client.fetchCard(set: "2xm", collectorNumber: "117")

        #expect(card.name == "Lightning Bolt")
        #expect(card.collectorNumber == "117")
    }

    // MARK: - Search

    @Test("searchCards returns decoded search result")
    func searchCardsSuccess() async throws {
        let httpClient = MockHTTPClient.success(data: ScryfallAPIClientTests.searchResultJSON)
        let client = ScryfallAPIClient(httpClient: httpClient)

        let result = try await client.searchCards(query: "lightning bolt")

        #expect(result.totalCards == 1)
        #expect(result.hasMore == false)
        #expect(result.data.count == 1)
        #expect(result.data.first?.name == "Lightning Bolt")
    }

    // MARK: - Collection

    @Test("fetchCardCollection returns decoded search result")
    func fetchCardCollectionSuccess() async throws {
        let httpClient = MockHTTPClient.success(data: ScryfallAPIClientTests.searchResultJSON)
        let client = ScryfallAPIClient(httpClient: httpClient)

        let identifiers: [[String: String]] = [
            ["set": "2xm", "collector_number": "117"]
        ]
        let result = try await client.fetchCardCollection(identifiers: identifiers)

        #expect(result.data.count == 1)
        #expect(result.data.first?.name == "Lightning Bolt")
    }

    // MARK: - HTTP Error Handling

    @Test("404 response throws cardNotFound error")
    func handlesNotFound() async {
        let httpClient = MockHTTPClient.success(
            data: ScryfallAPIClientTests.notFoundJSON,
            statusCode: 404
        )
        let client = ScryfallAPIClient(httpClient: httpClient)

        await #expect(throws: NetworkError.self) {
            _ = try await client.fetchCardByName("Nonexistent Card")
        }

        do {
            _ = try await client.fetchCardByName("Nonexistent Card")
        } catch let error as NetworkError {
            #expect(error == .notFound)
        } catch {
            Issue.record("Expected NetworkError.notFound but got \(error)")
        }
    }

    @Test("429 response throws rateLimited error")
    func handlesRateLimited() async {
        let httpClient = MockHTTPClient.success(
            data: Data(),
            statusCode: 429
        )
        let client = ScryfallAPIClient(httpClient: httpClient)

        do {
            _ = try await client.fetchCardByName("Lightning Bolt")
            Issue.record("Expected NetworkError.rateLimited")
        } catch let error as NetworkError {
            #expect(error == .rateLimited)
        } catch {
            Issue.record("Expected NetworkError.rateLimited but got \(error)")
        }
    }

    @Test("500 response throws serverError")
    func handlesServerError() async {
        let httpClient = MockHTTPClient.success(
            data: Data(),
            statusCode: 500
        )
        let client = ScryfallAPIClient(httpClient: httpClient)

        do {
            _ = try await client.fetchCardByName("Lightning Bolt")
            Issue.record("Expected NetworkError.serverError")
        } catch let error as NetworkError {
            #expect(error == .serverError(statusCode: 500))
        } catch {
            Issue.record("Expected NetworkError.serverError but got \(error)")
        }
    }

    // MARK: - Malformed JSON

    @Test("Malformed JSON throws decodingError")
    func handlesMalformedJSON() async {
        let httpClient = MockHTTPClient.success(data: ScryfallAPIClientTests.malformedJSON)
        let client = ScryfallAPIClient(httpClient: httpClient)

        do {
            _ = try await client.fetchCardByName("Lightning Bolt")
            Issue.record("Expected NetworkError.decodingError")
        } catch let error as NetworkError {
            if case .decodingError = error {
                // Expected
            } else {
                Issue.record("Expected NetworkError.decodingError but got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkError.decodingError but got \(error)")
        }
    }

    // MARK: - Network Error

    @Test("Network failure throws networkError")
    func handlesNetworkError() async {
        let urlError = URLError(.notConnectedToInternet)
        let httpClient = MockHTTPClient.failure(urlError)
        let client = ScryfallAPIClient(httpClient: httpClient)

        do {
            _ = try await client.fetchCardByName("Lightning Bolt")
            Issue.record("Expected NetworkError.networkError")
        } catch let error as NetworkError {
            if case .networkError = error {
                // Expected
            } else {
                Issue.record("Expected NetworkError.networkError but got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkError.networkError but got \(error)")
        }
    }

    // MARK: - Request Configuration

    @Test("Requests include correct User-Agent header")
    func requestsIncludeUserAgent() async throws {
        // Use a capturing HTTP client to inspect the request
        let capturingClient = CapturingHTTPClient(
            responseData: ScryfallAPIClientTests.singleCardJSON,
            statusCode: 200
        )
        let client = ScryfallAPIClient(httpClient: capturingClient)

        _ = try await client.fetchCardByName("Lightning Bolt")

        #expect(capturingClient.lastRequest?.value(forHTTPHeaderField: "User-Agent") == "MTGCardScanner/1.0")
    }
}

// MARK: - Capturing HTTP Client (for request inspection)

final class CapturingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let responseData: Data
    private let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(responseData: Data, statusCode: Int) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.scryfall.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}
