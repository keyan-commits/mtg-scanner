import Testing
import Foundation
@testable import MTGCardScanner

@Suite("MTGTop8ArchetypeIndex Tests")
struct MTGTop8ArchetypeIndexTests {

    // MARK: - Synthetic /search page HTML

    /// Mimics the actual MTGTop8 search-page structure: one <select>
    /// per format whose name attribute is `archetype_sel[<CODE>]`,
    /// containing one <option> per archetype with the numeric MTGTop8
    /// archetype ID as the value attribute. Note the unquoted attributes
    /// and the trailing space before `>` — both match the real markup.
    static let searchPageHTML = """
    <html><body>
    <form>
    <select name=archetype_sel[MO]>
        <option value="">All</option>
        <option value=42 >Boros Energy</option>
        <option value=99 >Affinity</option>
        <option value=12 >Burn</option>
    </select>
    <select name=archetype_sel[BL]>
        <option value="">All</option>
        <option value=353 >UW Heroic</option>
    </select>
    <select name=archetype_sel[ALCH]>
        <option value="">All</option>
        <option value=777 >Some Alchemy Deck</option>
    </select>
    </form>
    </body></html>
    """

    // MARK: - Parser

    @Test("Parser extracts archetypes from each known per-format select")
    func parserExtractsArchetypes() {
        let result = MTGTop8ArchetypeIndex.parseSearchPage(html: Self.searchPageHTML)
        // 3 from Modern + 1 from Block. Alchemy is unknown to our enum
        // and is silently skipped.
        #expect(result.count == 4)

        let modern = result.filter { $0.format == .modern }
        #expect(modern.count == 3)
        #expect(Set(modern.map(\.name)) == ["Boros Energy", "Affinity", "Burn"])

        let block = result.filter { $0.format == .block }
        #expect(block.count == 1)
        #expect(block[0].name == "UW Heroic")
        #expect(block[0].archetypeID == "353")
    }

    @Test("Parser captures archetype IDs as strings")
    func parserCapturesIDs() {
        let result = MTGTop8ArchetypeIndex.parseSearchPage(html: Self.searchPageHTML)
        let boros = result.first { $0.name == "Boros Energy" }
        #expect(boros?.archetypeID == "42")
    }

    @Test("Parser skips unknown format codes (Alchemy, Highlander variants)")
    func parserSkipsUnknownFormats() {
        let result = MTGTop8ArchetypeIndex.parseSearchPage(html: Self.searchPageHTML)
        let alchemy = result.filter { $0.archetypeID == "777" }
        #expect(alchemy.isEmpty)
    }

    @Test("Parser ignores the empty 'All' option")
    func parserIgnoresEmptyAll() {
        // Empty value="" options shouldn't produce IndexedArchetype
        // entries (they're the dropdown's "All formats" placeholder).
        let result = MTGTop8ArchetypeIndex.parseSearchPage(html: Self.searchPageHTML)
        #expect(result.allSatisfy { !$0.archetypeID.isEmpty })
        // No archetype named "All"
        #expect(result.allSatisfy { $0.name != "All" })
    }

    @Test("Parser returns empty for HTML with no relevant selects")
    func parserNoSelects() {
        let empty = "<html><body><p>nothing here</p></body></html>"
        let result = MTGTop8ArchetypeIndex.parseSearchPage(html: empty)
        #expect(result.isEmpty)
    }

    @Test("Parser handles multiple selects in one document")
    func parserMultipleSelects() {
        let result = MTGTop8ArchetypeIndex.parseSearchPage(html: Self.searchPageHTML)
        let formats = Set(result.map(\.format))
        #expect(formats == [.modern, .block])
    }

    // MARK: - MTGTop8Format codes

    @Test("Format codes match MTGTop8 URL parameters")
    func formatCodes() {
        #expect(MTGTop8Format.modern.code == "MO")
        #expect(MTGTop8Format.standard.code == "ST")
        #expect(MTGTop8Format.legacy.code == "LE")
        #expect(MTGTop8Format.vintage.code == "VI")
        #expect(MTGTop8Format.pioneer.code == "PI")
        #expect(MTGTop8Format.pauper.code == "PAU")
        #expect(MTGTop8Format.commander.code == "EDH")
        #expect(MTGTop8Format.premodern.code == "PREM")
        #expect(MTGTop8Format.block.code == "BL")
        #expect(MTGTop8Format.extended.code == "EX")
        #expect(MTGTop8Format.highlander.code == "HI")
        #expect(MTGTop8Format.peasant.code == "PEA")
    }

    // MARK: - End-to-end with stub HTTP client

    @Test("End-to-end: stub fetch + parse + cache + cache hit")
    func endToEnd() async throws {
        let stubClient = StubHTTPClient(
            payload: Self.searchPageHTML.data(using: .utf8)!
        )
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archetype-index-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let index = MTGTop8ArchetypeIndex(
            httpClient: stubClient,
            cacheDirectory: tempDir,
            ttl: 60
        )

        let archetypes = try await index.archetypes(forceRefresh: false)
        #expect(archetypes.count == 4)
        #expect(archetypes.contains { $0.name == "UW Heroic" })

        // Second call should hit the cache (no second network request)
        let cached = try await index.archetypes(forceRefresh: false)
        #expect(cached.count == 4)
        #expect(await stubClient.callCount == 1)
    }

    @Test("End-to-end: search finds Heroic across formats")
    func searchFindsHeroic() async throws {
        let stubClient = StubHTTPClient(
            payload: Self.searchPageHTML.data(using: .utf8)!
        )
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archetype-search-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let index = MTGTop8ArchetypeIndex(
            httpClient: stubClient,
            cacheDirectory: tempDir,
            ttl: 60
        )

        let hits = try await index.search(
            "heroic",
            in: MTGTop8Format.allCases,
            limit: 10
        )
        #expect(hits.count == 1)
        #expect(hits[0].name == "UW Heroic")
        #expect(hits[0].format == .block)
        #expect(hits[0].archetypeID == "353")
    }

    @Test("Search filters by requested format set")
    func searchFiltersByFormat() async throws {
        let stubClient = StubHTTPClient(
            payload: Self.searchPageHTML.data(using: .utf8)!
        )
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archetype-format-filter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let index = MTGTop8ArchetypeIndex(
            httpClient: stubClient,
            cacheDirectory: tempDir,
            ttl: 60
        )

        // Asking only for Modern excludes the Block-format Heroic
        let hits = try await index.search("heroic", in: [.modern], limit: 10)
        #expect(hits.isEmpty)
    }

    // MARK: - Abbreviation matching

    @Test("Implicit abbreviation: first letter of each word")
    func implicitAbbreviationBasic() {
        #expect(MTGTop8ArchetypeIndex.implicitAbbreviation(of: "Red Deck Wins") == "RDW")
        #expect(MTGTop8ArchetypeIndex.implicitAbbreviation(of: "Mono Black Control") == "MBC")
        #expect(MTGTop8ArchetypeIndex.implicitAbbreviation(of: "Ad Nauseam Tendrils") == "ANT")
        #expect(MTGTop8ArchetypeIndex.implicitAbbreviation(of: "Burn") == "B")
    }

    @Test("Implicit abbreviation handles punctuation and hyphens")
    func implicitAbbreviationPunctuation() {
        // Hyphens split words: "Mono-Black" → ["Mono", "Black"] → "MB"
        #expect(MTGTop8ArchetypeIndex.implicitAbbreviation(of: "Mono-Black Devotion") == "MBD")
        // Apostrophes don't split: "Urza's Saga" → ["Urza's", "Saga"] → "US"
        // Actually with letter-only splitting, "Urza's" is "Urza" + "s"
        #expect(MTGTop8ArchetypeIndex.implicitAbbreviation(of: "Urza's Saga") == "USS")
    }

    @Test("Search 'RDW' finds Red Deck Wins via abbreviation")
    func searchAbbreviationRDW() async throws {
        let html = """
        <select name=archetype_sel[MO]>
            <option value=226 >Red Deck Wins</option>
            <option value=12 >Burn</option>
            <option value=99 >Affinity</option>
        </select>
        """
        let stubClient = StubHTTPClient(payload: html.data(using: .utf8)!)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rdw-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let index = MTGTop8ArchetypeIndex(
            httpClient: stubClient, cacheDirectory: tempDir, ttl: 60
        )

        let hits = try await index.search("RDW", in: [.modern], limit: 10)
        #expect(hits.count == 1)
        #expect(hits[0].name == "Red Deck Wins")
        #expect(hits[0].archetypeID == "226")
    }

    @Test("Search 'MBC' finds Mono Black Control via abbreviation")
    func searchAbbreviationMBC() async throws {
        let html = """
        <select name=archetype_sel[ST]>
            <option value=1 >Mono Black Control</option>
            <option value=2 >Boros Aggro</option>
        </select>
        """
        let stubClient = StubHTTPClient(payload: html.data(using: .utf8)!)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mbc-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let index = MTGTop8ArchetypeIndex(
            httpClient: stubClient, cacheDirectory: tempDir, ttl: 60
        )

        let hits = try await index.search("MBC", in: [.standard], limit: 10)
        #expect(hits.count == 1)
        #expect(hits[0].name == "Mono Black Control")
    }

    @Test("Search abbreviation is case-insensitive")
    func searchAbbreviationCaseInsensitive() async throws {
        let html = """
        <select name=archetype_sel[MO]>
            <option value=1 >Red Deck Wins</option>
        </select>
        """
        let stubClient = StubHTTPClient(payload: html.data(using: .utf8)!)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rdw-case-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let index = MTGTop8ArchetypeIndex(
            httpClient: stubClient, cacheDirectory: tempDir, ttl: 60
        )

        let lower = try await index.search("rdw", in: [.modern], limit: 10)
        #expect(lower.count == 1)
        let mixed = try await index.search("rDw", in: [.modern], limit: 10)
        #expect(mixed.count == 1)
    }

    @Test("forceRefresh bypasses the cache and re-fetches")
    func forceRefreshHitsNetwork() async throws {
        let stubClient = StubHTTPClient(
            payload: Self.searchPageHTML.data(using: .utf8)!
        )
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archetype-force-refresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let index = MTGTop8ArchetypeIndex(
            httpClient: stubClient,
            cacheDirectory: tempDir,
            ttl: 60
        )

        _ = try await index.archetypes(forceRefresh: false)  // 1 call
        _ = try await index.archetypes(forceRefresh: true)   // 2 calls
        #expect(await stubClient.callCount == 2)
    }
}

// MARK: - Test stub HTTP client

/// Returns the same payload for every request and counts how many
/// requests it received. Used to validate caching behavior without
/// hitting the network.
private actor StubHTTPClient: HTTPClientProtocol {
    let payload: Data
    var callCount: Int = 0

    init(payload: Data) {
        self.payload = payload
    }

    nonisolated func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        await incrementCallCount()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (payload, response)
    }

    private func incrementCallCount() {
        callCount += 1
    }
}
