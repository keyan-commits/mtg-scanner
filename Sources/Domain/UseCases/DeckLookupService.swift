import Foundation

// MARK: - Models

struct FormatDeckData: Sendable, Identifiable {
    let id = UUID()
    let format: String
    let formatCode: String
    let isLegal: Bool
    let archetypes: [MTGTop8Archetype]
    let totalDecks: Int
}

struct DeckLookupResult: Sendable {
    let cardName: String
    let formatResults: [FormatDeckData]
    let commanderData: EDHRECCardData?
}

// MARK: - Protocol

protocol DeckLookupServiceProtocol: Sendable {
    func lookupDecks(for card: Card) async -> DeckLookupResult
}

// MARK: - Implementation

final class DeckLookupService: DeckLookupServiceProtocol, @unchecked Sendable {
    private let mtgTop8Service: MTGTop8ServiceProtocol
    private let edhrecService: EDHRECServiceProtocol

    /// Process-wide cache keyed by card name. MTGTop8 data changes
    /// slowly (weekly at most), so caching for the session is safe.
    private static let cacheLock = NSLock()
    private static var resultCache: [String: DeckLookupResult] = [:]

    /// Format display names mapped to MTGTop8 codes, in importance order.
    private static let formatMappings: [(name: String, code: String, key: String)] = [
        ("Standard", "ST", "standard"),
        ("Pioneer", "PI", "pioneer"),
        ("Modern", "MO", "modern"),
        ("Legacy", "LE", "legacy"),
        ("Vintage", "VI", "vintage"),
        ("Pauper", "PAU", "pauper"),
        ("Premodern", "PREM", "premodern"),
        ("Duel Commander", "EDH", "duel"),
        ("cEDH", "cEDH", "commander"),
    ]

    init(mtgTop8Service: MTGTop8ServiceProtocol, edhrecService: EDHRECServiceProtocol) {
        self.mtgTop8Service = mtgTop8Service
        self.edhrecService = edhrecService
    }

    func lookupDecks(for card: Card) async -> DeckLookupResult {
        let key = card.name.lowercased()

        // Check cache first
        Self.cacheLock.lock()
        let cached = Self.resultCache[key]
        Self.cacheLock.unlock()
        if let cached { return cached }

        let legalFormats = Self.formatMappings.filter { mapping in
            card.legalities.status(for: mapping.key) == .legal
        }

        // Fetch MTGTop8 data for all legal formats in parallel
        let formatResults = await fetchFormatResults(for: card.name, legalFormats: legalFormats)

        let result = DeckLookupResult(
            cardName: card.name,
            formatResults: formatResults,
            commanderData: nil
        )

        Self.cacheLock.lock()
        Self.resultCache[key] = result
        Self.cacheLock.unlock()

        return result
    }

    // MARK: - Private

    private func fetchFormatResults(
        for cardName: String,
        legalFormats: [(name: String, code: String, key: String)]
    ) async -> [FormatDeckData] {
        await withTaskGroup(of: FormatDeckData?.self, returning: [FormatDeckData].self) { group in
            for format in legalFormats {
                group.addTask {
                    do {
                        let data = try await self.mtgTop8Service.fetchCardData(name: cardName, format: format.code)
                        return FormatDeckData(
                            format: format.name,
                            formatCode: format.code,
                            isLegal: true,
                            archetypes: data.topArchetypes,
                            totalDecks: data.totalDecks
                        )
                    } catch {
                        // Gracefully handle per-format failures
                        return nil
                    }
                }
            }

            var results: [FormatDeckData] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }

            // Sort by format importance order
            let importanceOrder = Self.formatMappings.map(\.name)
            return results.sorted { a, b in
                let indexA = importanceOrder.firstIndex(of: a.format) ?? Int.max
                let indexB = importanceOrder.firstIndex(of: b.format) ?? Int.max
                return indexA < indexB
            }
        }
    }

    private func fetchCommanderData(for card: Card) async -> EDHRECCardData? {
        guard card.legalities.status(for: "commander") == .legal else {
            return nil
        }

        do {
            return try await edhrecService.fetchCardData(name: card.name)
        } catch {
            // Gracefully handle EDHREC failure
            return nil
        }
    }
}
