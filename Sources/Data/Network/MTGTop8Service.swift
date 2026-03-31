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

struct MTGTop8Deck: Sendable, Identifiable {
    let id = UUID()
    let deckID: String
    let name: String
    let player: String
    let event: String
    let finish: String
    let date: String
    let format: String
}

struct MTGTop8DecklistEntry: Sendable, Identifiable {
    let id = UUID()
    let quantity: Int
    let cardName: String
}

struct MTGTop8Decklist: Sendable {
    let mainboard: [MTGTop8DecklistEntry]
    let sideboard: [MTGTop8DecklistEntry]
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
    func fetchTopDecks(archetype: String, format: String?, cardName: String?) async throws -> [MTGTop8Deck]
    func fetchDecklist(deckID: String) async throws -> MTGTop8Decklist
}

// MARK: - Implementation

struct MTGTop8Service: MTGTop8ServiceProtocol {
    private let httpClient: HTTPClientProtocol
    private static let baseURL = "https://mtgtop8.com/search"

    init(httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchCardData(name: String) async throws -> MTGTop8CardData {
        try await performFetch(name: name, format: nil)
    }

    func fetchCardData(name: String, format: String) async throws -> MTGTop8CardData {
        try await performFetch(name: name, format: format)
    }

    private func performFetch(name: String, format: String?) async throws -> MTGTop8CardData {
        let searchURL = Self.buildSearchURL(for: name, format: format)

        guard let url = URL(string: searchURL) else {
            throw MTGTop8Error.parsingError
        }

        let request = URLRequest(url: url)

        let html: String
        do {
            let (data, _) = try await httpClient.data(for: request)
            // MTGTop8 uses Latin-1 encoding, not UTF-8
            guard let decoded = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
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
        // Split by table rows with hover_tr class (quotes may or may not be present)
        let rowPattern = #"<tr class=.?hover_tr.?>(.*?)</tr>"#
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

            // Extract deck name from anchor tag (href may or may not be quoted)
            let namePattern = #"<a\s+href=.?event\?[^>]*>([^<]+)</a>"#
            guard let nameRegex = try? NSRegularExpression(pattern: namePattern),
                  let nameMatch = nameRegex.firstMatch(in: rowContent, range: NSRange(rowContent.startIndex..., in: rowContent)),
                  let nameRange = Range(nameMatch.range(at: 1), in: rowContent) else { continue }
            let deckName = String(rowContent[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Extract format — look for known format names in the row
            let knownFormats = ["Standard", "Pioneer", "Modern", "Legacy", "Vintage", "Pauper"]
            let format = knownFormats.first { rowContent.contains($0) } ?? ""

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

    // MARK: - Top Decks for Archetype

    func fetchTopDecks(archetype: String, format: String?, cardName: String? = nil) async throws -> [MTGTop8Deck] {
        // Search MTGTop8 by card name, then filter to the target archetype.
        // MTGTop8 archetype IDs are numeric and format-specific, so we can't search by name directly.
        let searchCard = cardName ?? archetype
        let searchURL = Self.buildSearchURL(for: searchCard, format: format)

        guard let url = URL(string: searchURL) else { throw MTGTop8Error.parsingError }

        let html: String
        do {
            let (data, _) = try await httpClient.data(for: URLRequest(url: url))
            guard let decoded = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw MTGTop8Error.parsingError
            }
            html = decoded
        } catch let error as MTGTop8Error {
            throw error
        } catch {
            throw MTGTop8Error.networkError(underlying: error)
        }

        let allDecks = parseDecks(from: html)

        // Filter to decks matching the target archetype name
        let filtered = allDecks.filter { $0.name.lowercased() == archetype.lowercased() }
        return filtered.isEmpty ? allDecks : filtered
    }

    private func parseDecks(from html: String) -> [MTGTop8Deck] {
        let rowPattern = #"<tr class=.?hover_tr.?>(.*?)</tr>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: .dotMatchesLineSeparators) else {
            return []
        }

        let matches = rowRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var decks: [MTGTop8Deck] = []

        for match in matches.prefix(20) {
            guard let rowRange = Range(match.range(at: 1), in: html) else { continue }
            let row = String(html[rowRange])

            // Extract deck ID from href: event?e=xxx&d=xxx&f=xxx
            let linkPattern = #"<a\s+href=.?event\?e=(\d+)&d=(\d+)[^>]*>([^<]+)</a>"#
            guard let linkRegex = try? NSRegularExpression(pattern: linkPattern),
                  let linkMatch = linkRegex.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)),
                  let deckIDRange = Range(linkMatch.range(at: 2), in: row),
                  let nameRange = Range(linkMatch.range(at: 3), in: row) else { continue }

            let deckID = String(row[deckIDRange])
            let deckName = String(row[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Extract player from player link
            let playerPattern = #"<a\s+class=.?player.?\s+href=[^>]*>([^<]+)</a>"#
            let player: String
            if let playerRegex = try? NSRegularExpression(pattern: playerPattern),
               let playerMatch = playerRegex.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)),
               let playerRange = Range(playerMatch.range(at: 1), in: row) {
                player = String(row[playerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                player = ""
            }

            // Extract all <td> contents for event, finish, date
            let tdPattern = #"<td[^>]*>(.*?)</td>"#
            guard let tdRegex = try? NSRegularExpression(pattern: tdPattern, options: .dotMatchesLineSeparators) else { continue }
            let tdMatches = tdRegex.matches(in: row, range: NSRange(row.startIndex..., in: row))
            let tds = tdMatches.compactMap { m -> String? in
                guard let range = Range(m.range(at: 1), in: row) else { return nil }
                // Strip HTML tags
                let content = String(row[range])
                return content.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // tds: [deckName, player, format, event, level, finish, date]
            let knownFormats = ["Standard", "Pioneer", "Modern", "Legacy", "Vintage", "Pauper"]
            let format = knownFormats.first { f in tds.contains(where: { $0 == f }) } ?? ""
            let event = tds.count > 3 ? tds[3] : ""
            let finish = tds.count > 5 ? tds[5] : ""
            let date = tds.last ?? ""

            decks.append(MTGTop8Deck(
                deckID: deckID, name: deckName, player: player,
                event: event, finish: finish, date: date, format: format
            ))
        }

        return decks
    }

    // MARK: - Decklist Fetching

    func fetchDecklist(deckID: String) async throws -> MTGTop8Decklist {
        let urlString = "https://mtgtop8.com/mtgo?d=\(deckID)"
        guard let url = URL(string: urlString) else { throw MTGTop8Error.parsingError }

        let text: String
        do {
            let (data, _) = try await httpClient.data(for: URLRequest(url: url))
            guard let decoded = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw MTGTop8Error.parsingError
            }
            text = decoded
        } catch let error as MTGTop8Error {
            throw error
        } catch {
            throw MTGTop8Error.networkError(underlying: error)
        }

        return parseDecklist(from: text)
    }

    private func parseDecklist(from text: String) -> MTGTop8Decklist {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var mainboard: [MTGTop8DecklistEntry] = []
        var sideboard: [MTGTop8DecklistEntry] = []
        var isSideboard = false

        for line in lines {
            if line.lowercased() == "sideboard" {
                isSideboard = true
                continue
            }

            // Parse "4 Card Name"
            guard let spaceIndex = line.firstIndex(of: " ") else { continue }
            let qtyStr = String(line[line.startIndex..<spaceIndex])
            guard let qty = Int(qtyStr) else { continue }
            let cardName = String(line[line.index(after: spaceIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cardName.isEmpty else { continue }

            let entry = MTGTop8DecklistEntry(quantity: qty, cardName: cardName)
            if isSideboard {
                sideboard.append(entry)
            } else {
                mainboard.append(entry)
            }
        }

        return MTGTop8Decklist(mainboard: mainboard, sideboard: sideboard)
    }
}
