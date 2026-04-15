import Foundation

// MARK: - Models

/// One archetype scraped from MTGTop8's search page (`/search`).
///
/// MTGTop8's search form contains a per-format `<select name=archetype_sel[X]>`
/// dropdown listing every archetype that has tournament data. Scraping
/// that single page in one request gives us 1500+ archetypes across all
/// formats — far more comprehensive than the metagame snapshot pages.
struct IndexedArchetype: Codable, Sendable, Identifiable, Equatable {
    /// MTGTop8's numeric archetype identifier — used to construct
    /// archetype detail URLs (`/archetype?a=<id>&f=<format>`).
    let archetypeID: String
    let name: String
    let format: MTGTop8Format

    var id: String { "\(format.code)-\(archetypeID)" }
}

/// MTGTop8 format codes — what goes in the `?f=` query parameter.
///
/// Includes both current competitive formats and historical/eternal
/// formats so niche archetypes (Block-era Heroic, Peasant Goblins, etc.)
/// remain searchable.
enum MTGTop8Format: String, Codable, Sendable, CaseIterable, Identifiable {
    case standard = "ST"
    case pioneer = "PI"
    case modern = "MO"
    case legacy = "LE"
    case vintage = "VI"
    case pauper = "PAU"
    case commander = "EDH"
    case premodern = "PREM"
    case block = "BL"
    case extended = "EX"
    case highlander = "HI"
    case peasant = "PEA"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .pioneer: return "Pioneer"
        case .modern: return "Modern"
        case .legacy: return "Legacy"
        case .vintage: return "Vintage"
        case .pauper: return "Pauper"
        case .commander: return "Commander"
        case .premodern: return "Premodern"
        case .block: return "Block"
        case .extended: return "Extended"
        case .highlander: return "Highlander"
        case .peasant: return "Peasant"
        }
    }

    var code: String { rawValue }

    /// Reverse lookup by display name. Used by services that only
    /// have a display string (e.g., aggregation source rows that
    /// store `format` as text) and need to bin results by format
    /// code. Returns nil for unknown / unsupported formats.
    static func fromDisplayName(_ name: String) -> MTGTop8Format? {
        Self.allCases.first { $0.displayName == name }
    }
}

// MARK: - Cache envelope

/// Persisted cache entry — one file holds the complete archetype catalog
/// for every format MTGTop8 exposes (so a single network request keeps
/// us fully populated).
struct ArchetypeIndexCache: Codable, Sendable {
    let fetchedAt: Date
    let archetypes: [IndexedArchetype]
}

// MARK: - Errors

enum MTGTop8ArchetypeIndexError: Error {
    case networkError(underlying: Error)
    case parsingError
    case cacheIOError(underlying: Error)
}

// MARK: - Protocol

protocol MTGTop8ArchetypeIndexProtocol: Sendable {
    /// Returns the cached archetype catalog. Fetches from the network
    /// if no cache exists, the cache is older than `ttl`, or
    /// `forceRefresh` is true.
    func archetypes(forceRefresh: Bool) async throws -> [IndexedArchetype]

    /// Searches the catalog by archetype name (case-insensitive). Only
    /// archetypes whose `format` is in `formats` are considered. Returns
    /// up to `limit` results, ranked: exact → prefix → substring.
    func search(_ query: String, in formats: [MTGTop8Format], limit: Int) async throws -> [IndexedArchetype]
}

// MARK: - Implementation

/// Scrapes MTGTop8's `/search` page once and caches the resulting
/// archetype catalog locally.
///
/// Cache policy:
/// - **One file** for the entire catalog (`archetype_index.json`)
/// - **7-day TTL** — archetype names change slowly enough that this
///   stays fresh without hammering MTGTop8
/// - **Lazy**: only fetched the first time the user runs a deck search
/// - **`forceRefresh: true`** (used by pull-to-refresh) ignores the TTL
///
/// MTGTop8 has no API; we parse HTML defensively. The search page
/// structure we rely on:
///
/// ```html
/// <select name=archetype_sel[MO]>
///   <option value="">All</option>
///   <option value=42 >Boros Energy</option>
///   <option value=99 >Affinity</option>
///   ...
/// </select>
/// ```
///
/// One such `<select>` per format. The numeric `value` is the same
/// archetype ID used by `/archetype?a=<id>&f=<format>`, so we can hand
/// it directly to `MTGTop8Service.fetchDecksByArchetypeID`.
actor MTGTop8ArchetypeIndex: MTGTop8ArchetypeIndexProtocol {

    // MARK: - Config

    static let defaultTTL: TimeInterval = 7 * 24 * 60 * 60   // 7 days
    private static let searchURL = "https://mtgtop8.com/search"

    private let httpClient: HTTPClientProtocol
    private let cacheFile: URL
    private let ttl: TimeInterval

    /// In-memory mirror of the on-disk cache so repeated searches in
    /// the same session don't re-hit the filesystem.
    private var memoryCache: ArchetypeIndexCache?

    // MARK: - Init

    init(
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        cacheDirectory: URL? = nil,
        ttl: TimeInterval = MTGTop8ArchetypeIndex.defaultTTL
    ) {
        self.httpClient = httpClient
        self.ttl = ttl

        let directory: URL
        if let cacheDirectory {
            directory = cacheDirectory
        } else {
            // Default: Application Support / MTGCardScanner /
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            directory = base.appendingPathComponent("MTGCardScanner", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.cacheFile = directory.appendingPathComponent("archetype_index.json")
    }

    // MARK: - Public API

    func archetypes(forceRefresh: Bool = false) async throws -> [IndexedArchetype] {
        if !forceRefresh, let cached = loadCache(), !isStale(cached) {
            return cached.archetypes
        }

        let fresh = try await fetchAndParse()
        let entry = ArchetypeIndexCache(fetchedAt: Date(), archetypes: fresh)
        try saveCache(entry)
        memoryCache = entry
        return fresh
    }

    func search(_ query: String, in formats: [MTGTop8Format], limit: Int = 25) async throws -> [IndexedArchetype] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let lowered = trimmed.lowercased()
        let upperedAbbrev = trimmed.uppercased()

        let allArchetypes = (try? await archetypes(forceRefresh: false)) ?? []
        let formatSet = Set(formats)

        var exact: [IndexedArchetype] = []
        var abbreviation: [IndexedArchetype] = []
        var prefix: [IndexedArchetype] = []
        var substring: [IndexedArchetype] = []
        for archetype in allArchetypes where formatSet.contains(archetype.format) {
            let lower = archetype.name.lowercased()
            if lower == lowered {
                exact.append(archetype)
            } else if Self.implicitAbbreviation(of: archetype.name) == upperedAbbrev {
                // "RDW" matches "Red Deck Wins", "MBC" matches "Mono
                // Black Control", etc.
                abbreviation.append(archetype)
            } else if lower.hasPrefix(lowered) {
                prefix.append(archetype)
            } else if lower.contains(lowered) {
                substring.append(archetype)
            }
        }

        let byName: (IndexedArchetype, IndexedArchetype) -> Bool = { $0.name < $1.name }
        return Array(
            (exact.sorted(by: byName)
             + abbreviation.sorted(by: byName)
             + prefix.sorted(by: byName)
             + substring.sorted(by: byName)
            ).prefix(limit)
        )
    }

    /// Computes the first-letter-of-each-word implicit abbreviation for
    /// an archetype name. "Red Deck Wins" → "RDW", "Mono Black Control"
    /// → "MBC", "Ad Nauseam Tendrils" → "ANT".
    ///
    /// Only word-leading alphabetic characters are kept — color codes
    /// like "UW" in "UW Heroic" stay intact since "UW" is itself the
    /// first word.
    static func implicitAbbreviation(of name: String) -> String {
        name.split(whereSeparator: { !$0.isLetter })
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
    }

    // MARK: - Cache I/O

    private func loadCache() -> ArchetypeIndexCache? {
        if let inMemory = memoryCache { return inMemory }
        guard FileManager.default.fileExists(atPath: cacheFile.path) else { return nil }
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(ArchetypeIndexCache.self, from: data)
            memoryCache = decoded
            return decoded
        } catch {
            // Corrupt cache — discard and re-fetch on next call
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }

    private func saveCache(_ cache: ArchetypeIndexCache) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheFile, options: .atomic)
        } catch {
            throw MTGTop8ArchetypeIndexError.cacheIOError(underlying: error)
        }
    }

    private func isStale(_ cache: ArchetypeIndexCache) -> Bool {
        Date().timeIntervalSince(cache.fetchedAt) > ttl
    }

    // MARK: - Network + parsing

    private func fetchAndParse() async throws -> [IndexedArchetype] {
        guard let url = URL(string: Self.searchURL) else {
            throw MTGTop8ArchetypeIndexError.parsingError
        }

        let html: String
        do {
            let (data, _) = try await httpClient.data(for: URLRequest(url: url))
            // MTGTop8 sometimes serves Latin-1 (player names with accents).
            guard let decoded = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw MTGTop8ArchetypeIndexError.parsingError
            }
            html = decoded
        } catch let error as MTGTop8ArchetypeIndexError {
            throw error
        } catch {
            throw MTGTop8ArchetypeIndexError.networkError(underlying: error)
        }

        return Self.parseSearchPage(html: html)
    }

    /// Parses MTGTop8's `/search` page HTML into a complete archetype
    /// catalog. Defensive: returns whatever it can find, never throws —
    /// if MTGTop8 changes their layout, the user sees no online results
    /// instead of a crash, and we update the parser.
    static func parseSearchPage(html: String) -> [IndexedArchetype] {
        // Each format owns one archetype dropdown:
        //   <select ... name=archetype_sel[<CODE>] ...> ... </select>
        let selectPattern = #"<select[^>]*name=archetype_sel\[([A-Z]+)\][^>]*>([\s\S]*?)</select>"#
        guard let selectRegex = try? NSRegularExpression(pattern: selectPattern) else {
            return []
        }

        var results: [IndexedArchetype] = []
        let fullRange = NSRange(html.startIndex..., in: html)
        let selectMatches = selectRegex.matches(in: html, range: fullRange)

        for selectMatch in selectMatches {
            guard let codeRange = Range(selectMatch.range(at: 1), in: html),
                  let bodyRange = Range(selectMatch.range(at: 2), in: html) else {
                continue
            }
            let code = String(html[codeRange])
            // Skip formats we don't expose (Alchemy, Challenger, etc.).
            // Unknown codes silently fall through — adding a new format
            // to the enum is enough to start surfacing it.
            guard let format = MTGTop8Format(rawValue: code) else { continue }

            let body = String(html[bodyRange])
            results.append(contentsOf: parseOptions(in: body, format: format))
        }

        return results
    }

    /// Parses every `<option value="N">Name</option>` inside a single
    /// `<select>` body. The MTGTop8 markup uses unquoted attributes
    /// (`<option value=42 >`), so the regex tolerates that.
    private static func parseOptions(in body: String, format: MTGTop8Format) -> [IndexedArchetype] {
        let optionPattern = #"<option\s+value=(\d+)[^>]*>([^<]+)</option>"#
        guard let optionRegex = try? NSRegularExpression(pattern: optionPattern) else {
            return []
        }
        let range = NSRange(body.startIndex..., in: body)
        return optionRegex.matches(in: body, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: body),
                  let nameRange = Range(match.range(at: 2), in: body) else { return nil }
            let id = String(body[idRange])
            let name = String(body[nameRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return IndexedArchetype(
                archetypeID: id,
                name: name,
                format: format
            )
        }
    }
}
