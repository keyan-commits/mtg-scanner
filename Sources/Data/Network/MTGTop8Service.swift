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
    /// MTGTop8 tournament tier — number of stars in the level column.
    /// 1 = local / FNM-tier, 5 = premier (Pro Tour, Worlds, GP). Lets
    /// the UI surface "this is a 4-star event" so the user knows how
    /// prominent each result is. 0 means no stars / unknown.
    let level: Int
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
    func fetchTopDecks(
        archetype: String,
        format: String?,
        cardName: String?,
        maxPlacement: Int?
    ) async throws -> [MTGTop8Deck]
    /// Fetches decks for an MTGTop8 archetype using its native numeric
    /// archetype ID — this avoids the card-name-search workaround that
    /// `fetchTopDecks(archetype:format:cardName:)` uses, so results are
    /// the actual list MTGTop8 displays for that archetype page.
    func fetchDecksByArchetypeID(
        _ archetypeID: String,
        format: String,
        maxPlacement: Int?
    ) async throws -> [MTGTop8Deck]
    /// Returns the most recent #1 finish for an archetype, or nil if
    /// there are none. Used by the Browse Archetypes screen.
    func fetchLatestTop1(archetypeID: String, format: String) async throws -> MTGTop8Deck?
    /// Returns the most recent deck for an archetype regardless of
    /// placement. Unlike `fetchLatestTop1`, this never returns nil
    /// for a format that has any tournament data — it's the right
    /// primitive for "give me a representative deck for this format"
    /// (used by `CommonCardsAggregator` so every format the archetype
    /// exists in contributes to the universal-cards intersection).
    func fetchMostRecentDeck(archetypeID: String, format: String) async throws -> MTGTop8Deck?
    func fetchDecklist(deckID: String) async throws -> MTGTop8Decklist
}

extension MTGTop8ServiceProtocol {
    /// Convenience overload that preserves the older 3-argument call site
    /// (no placement filter).
    func fetchTopDecks(
        archetype: String,
        format: String?,
        cardName: String?
    ) async throws -> [MTGTop8Deck] {
        try await fetchTopDecks(
            archetype: archetype,
            format: format,
            cardName: cardName,
            maxPlacement: nil
        )
    }
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

    func fetchTopDecks(
        archetype: String,
        format: String?,
        cardName: String? = nil,
        maxPlacement: Int? = nil
    ) async throws -> [MTGTop8Deck] {
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

        // Filter to decks matching the target archetype name. Strip any
        // parenthesized suffix from our query (e.g. "Affinity (Robots)")
        // so we still match MTGTop8's bare archetype name "Affinity".
        let normalized = Self.normalizeArchetypeName(archetype)
        let nameFiltered = allDecks.filter { deck in
            let deckName = Self.normalizeArchetypeName(deck.name)
            return deckName == normalized || deckName.contains(normalized) || normalized.contains(deckName)
        }

        let archetypeFiltered = nameFiltered.isEmpty ? allDecks : nameFiltered

        guard let maxPlacement else { return archetypeFiltered }
        return archetypeFiltered.filter { deck in
            guard let placement = Self.parsePlacement(deck.finish) else { return false }
            return placement <= maxPlacement
        }
    }

    /// Returns the most recent top-1 finish for an archetype, or nil
    /// if no #1 finishes exist in the recent decks list. Used by the
    /// Browse Archetypes screen to display each archetype's latest
    /// winning deck.
    ///
    /// MTGTop8 returns decks in date-descending order, so the first
    /// deck whose finish parses to 1 is the most recent winner.
    func fetchLatestTop1(archetypeID: String, format: String) async throws -> MTGTop8Deck? {
        let decks = try await fetchDecksByArchetypeID(
            archetypeID,
            format: format,
            maxPlacement: 1
        )
        return decks.first
    }

    func fetchMostRecentDeck(archetypeID: String, format: String) async throws -> MTGTop8Deck? {
        // No placement filter — MTGTop8 returns rows in date-desc
        // order, so the first row is the most recent representative
        // deck regardless of finish.
        let decks = try await fetchDecksByArchetypeID(
            archetypeID,
            format: format,
            maxPlacement: nil
        )
        return decks.first
    }

    /// Lowercases and strips any parenthesized suffix (e.g. "(Robots)").
    /// Used for archetype-name comparison so curated names match MTGTop8.
    static func normalizeArchetypeName(_ name: String) -> String {
        let lowered = name.lowercased()
        guard let parenIdx = lowered.firstIndex(of: "(") else {
            return lowered.trimmingCharacters(in: .whitespaces)
        }
        return String(lowered[..<parenIdx]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Top Decks by Archetype ID (native MTGTop8 endpoint)

    func fetchDecksByArchetypeID(
        _ archetypeID: String,
        format: String,
        maxPlacement: Int? = nil
    ) async throws -> [MTGTop8Deck] {
        // The `/archetype?a=N&f=X` page only shows ONE representative
        // deck for the archetype. To get the full list of recent
        // tournament decks tagged with this archetype we have to hit
        // the search endpoint with the archetype filter applied — same
        // as what the form on /search submits when the user picks an
        // archetype from the dropdown. The bracket characters need to
        // be percent-encoded.
        let urlString = "https://mtgtop8.com/search?format=\(format)&archetype_sel%5B\(format)%5D=\(archetypeID)&MD_check=1&SB_check=1"
        guard let url = URL(string: urlString) else { throw MTGTop8Error.parsingError }

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

        let decks = parseDecks(from: html)
        guard let maxPlacement else { return decks }
        return decks.filter { deck in
            guard let placement = Self.parsePlacement(deck.finish) else { return false }
            return placement <= maxPlacement
        }
    }

    /// Parses the leading numeric placement out of an MTGTop8 finish
    /// string. Handles "1st", "5", "T8", "9-12", "5-8", and similar.
    /// Returns nil for unparseable inputs (e.g., "—", "").
    static func parsePlacement(_ finish: String) -> Int? {
        let trimmed = finish.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Strip a leading "T" (top-N) marker — "T8" → "8"
        let withoutT: String
        if let first = trimmed.first, first == "T" || first == "t" {
            withoutT = String(trimmed.dropFirst())
        } else {
            withoutT = trimmed
        }

        // Pull the leading run of digits
        var digits = ""
        for ch in withoutT {
            if ch.isNumber {
                digits.append(ch)
            } else {
                break
            }
        }
        return Int(digits)
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

            // Extract deck ID from href. Real MTGTop8 hrefs come in two
            // shapes — quoted/unquoted and with/without a leading slash:
            //   href="event?e=N&d=N&f=X"
            //   href=/event?e=N&d=N&f=X
            // The regex tolerates the optional opening quote and the
            // optional leading slash.
            let linkPattern = #"<a\s+href=.?/?event\?e=(\d+)&d=(\d+)[^>]*>([^<]+)</a>"#
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

            // Extract all <td> contents. Keep BOTH the raw HTML (for
            // counting star images in the level column) and the
            // stripped text (for the displayable fields).
            let tdPattern = #"<td[^>]*>(.*?)</td>"#
            guard let tdRegex = try? NSRegularExpression(pattern: tdPattern, options: .dotMatchesLineSeparators) else { continue }
            let tdMatches = tdRegex.matches(in: row, range: NSRange(row.startIndex..., in: row))
            let rawTds: [String] = tdMatches.compactMap { m in
                guard let range = Range(m.range(at: 1), in: row) else { return nil }
                return String(row[range])
            }
            let tds = rawTds.map { content in
                content.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Real row layout (verified against MTGTop8 /search results):
            //   tds[0] = checkbox cell
            //   tds[1] = deck name
            //   tds[2] = player name
            //   tds[3] = format
            //   tds[4] = event
            //   tds[5] = level (star icons; empty after stripping HTML)
            //   tds[6] = finish placement (e.g. "1", "8", "3-4", "T8")
            //   tds[7] = date
            //
            // Counting from the END of the list is more robust than
            // hardcoded indices because some queries omit the leading
            // checkbox column. Last → date, second-last → finish,
            // third-last → level (star images), fourth-last → event.
            let knownFormats = ["Standard", "Pioneer", "Modern", "Legacy", "Vintage", "Pauper"]
            let format = knownFormats.first { f in tds.contains(where: { $0 == f }) } ?? ""
            let date = tds.last ?? ""
            let finish = tds.count >= 2 ? tds[tds.count - 2] : ""
            let event = tds.count >= 4 ? tds[tds.count - 4] : ""

            // Star count comes from the raw HTML — count occurrences
            // of `<img` inside the level cell (third from end). Each
            // star is one img tag (`<img src=/graph/star.png>`).
            let level: Int
            if rawTds.count >= 3 {
                let levelCell = rawTds[rawTds.count - 3]
                level = Self.countOccurrences(of: "<img", in: levelCell)
            } else {
                level = 0
            }

            decks.append(MTGTop8Deck(
                deckID: deckID, name: deckName, player: player,
                event: event, finish: finish, date: date, format: format,
                level: level
            ))
        }

        return decks
    }

    /// Counts non-overlapping occurrences of `needle` in `haystack`.
    /// Used to count `<img` tags in the level cell (each represents
    /// one star).
    private static func countOccurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<haystack.endIndex
        }
        return count
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
