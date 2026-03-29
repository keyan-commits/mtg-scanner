import Foundation

// MARK: - Scryfall Error

enum ScryfallError: Error, Equatable, Sendable {
    case cardNotFound
    case rateLimited
    case serverError(statusCode: Int)
    case decodingError(String)
    case networkError(String)

    static func == (lhs: ScryfallError, rhs: ScryfallError) -> Bool {
        switch (lhs, rhs) {
        case (.cardNotFound, .cardNotFound):
            return true
        case (.rateLimited, .rateLimited):
            return true
        case (.serverError(let lCode), .serverError(let rCode)):
            return lCode == rCode
        case (.decodingError(let lMsg), .decodingError(let rMsg)):
            return lMsg == rMsg
        case (.networkError(let lMsg), .networkError(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

// MARK: - API Client Protocol

protocol ScryfallAPIClientProtocol: Sendable {
    func fetchCardByName(_ name: String) async throws -> ScryfallCardDTO
    func fetchCard(set: String, collectorNumber: String) async throws -> ScryfallCardDTO
    func searchCards(query: String) async throws -> ScryfallSearchDTO
    func fetchCardCollection(identifiers: [[String: String]]) async throws -> ScryfallSearchDTO
}

// MARK: - Scryfall API Client

struct ScryfallAPIClient: ScryfallAPIClientProtocol {
    private let baseURL = "https://api.scryfall.com"
    private let userAgent = "MTGCardScanner/1.0"
    private let httpClient: HTTPClientProtocol
    private let decoder: JSONDecoder

    init(httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.httpClient = httpClient
        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    func fetchCardByName(_ name: String) async throws -> ScryfallCardDTO {
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ScryfallError.networkError("Invalid card name encoding")
        }
        let url = URL(string: "\(baseURL)/cards/named?fuzzy=\(encodedName)")!
        let request = makeRequest(url: url)
        return try await perform(request: request)
    }

    func fetchCard(set: String, collectorNumber: String) async throws -> ScryfallCardDTO {
        let url = URL(string: "\(baseURL)/cards/\(set)/\(collectorNumber)")!
        let request = makeRequest(url: url)
        return try await perform(request: request)
    }

    func searchCards(query: String) async throws -> ScryfallSearchDTO {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ScryfallError.networkError("Invalid search query encoding")
        }
        let url = URL(string: "\(baseURL)/cards/search?q=\(encodedQuery)")!
        let request = makeRequest(url: url)
        return try await perform(request: request)
    }

    func fetchCardCollection(identifiers: [[String: String]]) async throws -> ScryfallSearchDTO {
        let url = URL(string: "\(baseURL)/cards/collection")!
        var request = makeRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["identifiers": identifiers]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await perform(request: request)
    }

    // MARK: - Private Helpers

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform<T: Decodable>(request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw ScryfallError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScryfallError.networkError("Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 404:
            throw ScryfallError.cardNotFound
        case 429:
            throw ScryfallError.rateLimited
        default:
            throw ScryfallError.serverError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ScryfallError.decodingError(error.localizedDescription)
        }
    }
}
