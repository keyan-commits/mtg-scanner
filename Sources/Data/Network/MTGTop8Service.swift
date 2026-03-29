import Foundation

// MARK: - Models

struct MTGTop8CardData: Sendable {
    let cardName: String
    let totalDecks: Int
    let topArchetypes: [MTGTop8Archetype]
    let searchURL: String
    let format: String?
}

struct MTGTop8Archetype: Sendable, Identifiable {
    let id = UUID()
    let name: String
    let format: String
    let count: Int
}

// MARK: - Error

enum MTGTop8Error: Error {
    case networkError(underlying: Error)
    case parsingError
}

// MARK: - Protocol

protocol MTGTop8ServiceProtocol: Sendable {
    func fetchCardData(name: String) async throws -> MTGTop8CardData
    func fetchCardData(name: String, format: String) async throws -> MTGTop8CardData
}

// MARK: - Implementation

struct MTGTop8Service: MTGTop8ServiceProtocol {
    private let httpClient: HTTPClientProtocol
    private static let baseURL = "https://mtgtop8.com/search"

    init(httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchCardData(name: String) async throws -> MTGTop8CardData {
        try await fetchCardData(name: name, format: nil)
    }

    func fetchCardData(name: String, format: String) async throws -> MTGTop8CardData {
        try await fetchCardData(name: name, format: format)
    }

    private func fetchCardData(name: String, format: String?) async throws -> MTGTop8CardData {
        let searchURL = Self.buildSearchURL(for: name, format: format)

        guard let url = URL(string: searchURL) else {
            throw MTGTop8Error.parsingError
        }

        let request = URLRequest(url: url)

        let html: String
        do {
            let (data, _) = try await httpClient.data(for: request)
            guard let decoded = String(data: data, encoding: .utf8) else {
                throw MTGTop8Error.parsingError
            }
            html = decoded
        } catch let error as MTGTop8Error {
            throw error
        } catch {
            throw MTGTop8Error.networkError(underlying: error)
        }

        let totalDecks = try parseTotalDecks(from: html)
        let archetypes = parseArchetypes(from: html)

        return MTGTop8CardData(
            cardName: name,
            totalDecks: totalDecks,
            topArchetypes: archetypes,
            searchURL: searchURL,
            format: format
        )
    }

    // MARK: - URL Construction

    private static func buildSearchURL(for cardName: String, format: String? = nil) -> String {
        let encoded = cardName.replacingOccurrences(of: " ", with: "+")
        var url = "\(baseURL)?MD_check=1&SB_check=1&cards=\(encoded)"
        if let format {
            url += "&format=\(format)"
        }
        return url
    }

    // MARK: - HTML Parsing

    private func parseTotalDecks(from html: String) throws -> Int {
        let pattern = #"(\d+)\s+decks?\s+matching"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let countRange = Range(match.range(at: 1), in: html) else {
            throw MTGTop8Error.parsingError
        }
        return Int(html[countRange]) ?? 0
    }

    private func parseArchetypes(from html: String) -> [MTGTop8Archetype] {
        // Split by table rows with hover_tr class
        let rowPattern = #"<tr class="hover_tr">(.*?)</tr>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: .dotMatchesLineSeparators) else {
            return []
        }

        let matches = rowRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        struct RawDeck {
            let name: String
            let format: String
        }

        var rawDecks: [RawDeck] = []

        for match in matches {
            guard let rowRange = Range(match.range(at: 1), in: html) else { continue }
            let rowContent = String(html[rowRange])

            // Extract deck name from anchor tag
            let namePattern = #"<a\s+href="event\?[^"]*">([^<]+)</a>"#
            guard let nameRegex = try? NSRegularExpression(pattern: namePattern),
                  let nameMatch = nameRegex.firstMatch(in: rowContent, range: NSRange(rowContent.startIndex..., in: rowContent)),
                  let nameRange = Range(nameMatch.range(at: 1), in: rowContent) else { continue }
            let deckName = String(rowContent[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Extract format from the second <td> (first td after the anchor)
            let tdPattern = #"<td>([^<]+)</td>"#
            guard let tdRegex = try? NSRegularExpression(pattern: tdPattern) else { continue }
            let tdMatches = tdRegex.matches(in: rowContent, range: NSRange(rowContent.startIndex..., in: rowContent))

            // The first plain <td> after the anchor-containing td holds the format
            guard let firstTdMatch = tdMatches.first,
                  let formatRange = Range(firstTdMatch.range(at: 1), in: rowContent) else { continue }
            let format = String(rowContent[formatRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            rawDecks.append(RawDeck(name: deckName, format: format))
        }

        // Group by archetype name and count
        var grouped: [String: (format: String, count: Int)] = [:]
        for deck in rawDecks {
            if let existing = grouped[deck.name] {
                grouped[deck.name] = (format: existing.format, count: existing.count + 1)
            } else {
                grouped[deck.name] = (format: deck.format, count: 1)
            }
        }

        // Sort by count descending, take top 10
        let sorted = grouped.sorted { $0.value.count > $1.value.count }
        return Array(sorted.prefix(10)).map { key, value in
            MTGTop8Archetype(name: key, format: value.format, count: value.count)
        }
    }
}
