import Foundation

// MARK: - EDHREC Models

struct EDHRECCardData: Sendable {
    let cardName: String
    let numDecks: Int
    let potentialDecks: Int
    let inclusionPercent: Double
    let topCommanders: [EDHRECCommander]
}

struct EDHRECCommander: Sendable, Identifiable {
    let id = UUID()
    let name: String
    let numDecks: Int
    let potentialDecks: Int
    let inclusionPercent: Double
    let imageURI: String?
}

// MARK: - EDHREC Service Protocol

protocol EDHRECServiceProtocol: Sendable {
    func fetchCardData(name: String) async throws -> EDHRECCardData
}

// MARK: - EDHREC Service

struct EDHRECService: EDHRECServiceProtocol {
    private let baseURL = "https://json.edhrec.com/pages/cards"
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchCardData(name: String) async throws -> EDHRECCardData {
        let sanitized = sanitizeName(name)
        let urlString = "\(baseURL)/\(sanitized).json"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }
        let request = URLRequest(url: url)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw NetworkError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 404 {
            throw NetworkError.notFound
        }

        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            throw NetworkError.networkError("HTTP \(httpResponse.statusCode)")
        }

        return try parseResponse(data: data)
    }

    // MARK: - Name Sanitization

    private func sanitizeName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "-")
    }

    // MARK: - JSON Parsing

    private func parseResponse(data: Data) throws -> EDHRECCardData {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw NetworkError.decodingError(error.localizedDescription)
        }

        guard let root = json as? [String: Any],
              let container = root["container"] as? [String: Any],
              let jsonDict = container["json_dict"] as? [String: Any],
              let card = jsonDict["card"] as? [String: Any],
              let cardName = card["name"] as? String,
              let numDecks = card["num_decks"] as? Int,
              let potentialDecks = card["potential_decks"] as? Int
        else {
            throw NetworkError.decodingError("Missing required card fields in response")
        }

        let inclusionPercent = potentialDecks > 0
            ? Double(numDecks) / Double(potentialDecks) * 100
            : 0

        let commanders = parseTopCommanders(from: jsonDict)

        return EDHRECCardData(
            cardName: cardName,
            numDecks: numDecks,
            potentialDecks: potentialDecks,
            inclusionPercent: inclusionPercent,
            topCommanders: commanders
        )
    }

    private func parseTopCommanders(from jsonDict: [String: Any]) -> [EDHRECCommander] {
        guard let cardlists = jsonDict["cardlists"] as? [[String: Any]] else {
            return []
        }

        guard let topCommandersList = cardlists.first(where: { ($0["tag"] as? String) == "topcommanders" }),
              let cardviews = topCommandersList["cardviews"] as? [[String: Any]]
        else {
            return []
        }

        let commanders = cardviews.prefix(10).compactMap { entry -> EDHRECCommander? in
            guard let name = entry["name"] as? String,
                  let inclusion = entry["inclusion"] as? Int,
                  let potential = entry["potential_decks"] as? Int
            else {
                return nil
            }

            let percent = potential > 0
                ? Double(inclusion) / Double(potential) * 100
                : 0

            return EDHRECCommander(
                name: name,
                numDecks: inclusion,
                potentialDecks: potential,
                inclusionPercent: percent,
                imageURI: entry["image"] as? String
            )
        }

        return commanders
    }
}
