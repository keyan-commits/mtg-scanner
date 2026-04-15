import Foundation

// MARK: - Persisted DTO

private struct PersistedDecklist: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let quantity: Int
        let cardName: String
    }

    let mainboard: [Entry]
    let sideboard: [Entry]

    init(_ list: MTGTop8Decklist) {
        self.mainboard = list.mainboard.map { Entry(quantity: $0.quantity, cardName: $0.cardName) }
        self.sideboard = list.sideboard.map { Entry(quantity: $0.quantity, cardName: $0.cardName) }
    }

    var domain: MTGTop8Decklist {
        MTGTop8Decklist(
            mainboard: mainboard.map { MTGTop8DecklistEntry(quantity: $0.quantity, cardName: $0.cardName) },
            sideboard: sideboard.map { MTGTop8DecklistEntry(quantity: $0.quantity, cardName: $0.cardName) }
        )
    }
}

private struct DecklistCacheEntry: Codable, Sendable {
    let fetchedAt: Date
    let decklist: PersistedDecklist
}

private struct DecklistCacheFile: Codable, Sendable {
    var entries: [String: DecklistCacheEntry]
}

// MARK: - Protocol

protocol DecklistCacheProtocol: Sendable {
    /// Returns the decklist for `deckID`. Hits the cache when fresh,
    /// otherwise asks the MTGTop8 service. Returns nil on network
    /// failure (the caller decides whether to surface the error or
    /// degrade gracefully).
    func decklist(deckID: String, forceRefresh: Bool) async -> MTGTop8Decklist?

    /// Wipes every entry. Used by the "refresh all" admin actions.
    func clearAll() async
}

// MARK: - Implementation

/// File-backed cache for `MTGTop8Service.fetchDecklist(deckID:)`.
///
/// Decklists on MTGTop8 are immutable once an event is over — the
/// only reason to refresh is if MTGTop8 corrects a transcription
/// error. We use a long TTL (14 days) since the underlying data
/// effectively never changes.
///
/// Used by `CommonCardsAggregator` to avoid re-fetching the same
/// decklist when multiple major archetypes share matched MTGTop8
/// archetypes (or when the user revisits a major archetype detail
/// page).
actor DecklistCache: DecklistCacheProtocol {

    static let defaultTTL: TimeInterval = 14 * 24 * 60 * 60   // 14 days

    private let service: MTGTop8ServiceProtocol
    private let cacheFile: URL
    private let ttl: TimeInterval

    private var memoryCache: DecklistCacheFile?

    init(
        service: MTGTop8ServiceProtocol = MTGTop8Service(),
        cacheDirectory: URL? = nil,
        ttl: TimeInterval = DecklistCache.defaultTTL
    ) {
        self.service = service
        self.ttl = ttl

        let directory: URL
        if let cacheDirectory {
            directory = cacheDirectory
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            directory = base.appendingPathComponent("MTGCardScanner", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.cacheFile = directory.appendingPathComponent("decklist_cache.json")
    }

    // MARK: - Public API

    func decklist(deckID: String, forceRefresh: Bool = false) async -> MTGTop8Decklist? {
        loadIfNeeded()
        if !forceRefresh,
           let entry = memoryCache?.entries[deckID],
           !isStale(entry) {
            return entry.decklist.domain
        }
        guard let fresh = try? await service.fetchDecklist(deckID: deckID) else {
            return nil
        }
        var file = memoryCache ?? DecklistCacheFile(entries: [:])
        file.entries[deckID] = DecklistCacheEntry(
            fetchedAt: Date(),
            decklist: PersistedDecklist(fresh)
        )
        memoryCache = file
        save()
        return fresh
    }

    func clearAll() async {
        memoryCache = DecklistCacheFile(entries: [:])
        save()
    }

    // MARK: - Cache I/O

    private func loadIfNeeded() {
        if memoryCache != nil { return }
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            memoryCache = DecklistCacheFile(entries: [:])
            return
        }
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            memoryCache = try decoder.decode(DecklistCacheFile.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: cacheFile)
            memoryCache = DecklistCacheFile(entries: [:])
        }
    }

    private func save() {
        guard let memoryCache else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(memoryCache)
            try data.write(to: cacheFile, options: .atomic)
        } catch {
            // Best-effort persistence
        }
    }

    private func isStale(_ entry: DecklistCacheEntry) -> Bool {
        Date().timeIntervalSince(entry.fetchedAt) > ttl
    }
}
