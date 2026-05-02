import Foundation

// MARK: - Persisted DTO

/// On-disk shape for the cache. Mirrors `MTGTop8Deck` minus the
/// `id = UUID()` (which is auto-generated and not Codable-friendly).
private struct PersistedTopDeck: Codable, Sendable {
    let deckID: String
    let name: String
    let player: String
    let event: String
    let finish: String
    let date: String
    let format: String
    /// MTGTop8 tournament tier (1-5 stars). Optional for backwards
    /// compatibility with caches written before the field existed.
    let level: Int?

    init(_ deck: MTGTop8Deck) {
        self.deckID = deck.deckID
        self.name = deck.name
        self.player = deck.player
        self.event = deck.event
        self.finish = deck.finish
        self.date = deck.date
        self.format = deck.format
        self.level = deck.level
    }

    var domain: MTGTop8Deck {
        MTGTop8Deck(
            deckID: deckID,
            name: name,
            player: player,
            event: event,
            finish: finish,
            date: date,
            format: format,
            level: level ?? 0
        )
    }
}

private struct LatestTopFinishesCacheEntry: Codable, Sendable {
    let fetchedAt: Date
    /// Nil means we successfully looked up the archetype but found no
    /// recent #1 finish — cached so we don't keep retrying every view.
    let deck: PersistedTopDeck?
}

private struct LatestTopFinishesCacheFile: Codable, Sendable {
    var entries: [String: LatestTopFinishesCacheEntry]
}

// MARK: - Errors

enum LatestTopFinishesCacheError: Error {
    case ioError(underlying: Error)
}

// MARK: - Protocol

protocol LatestTopFinishesCacheProtocol: Sendable {
    /// Returns the most recent #1-finish deck for an archetype.
    /// Hits the cache when fresh; otherwise asks the MTGTop8 service
    /// and stores the result. Returns nil if the archetype has no
    /// recent #1 finish in MTGTop8's data.
    func latestTop1(
        archetypeID: String,
        format: String,
        forceRefresh: Bool
    ) async -> MTGTop8Deck?

    /// Wipes every entry in the cache. Used by the "Refresh All"
    /// toolbar action in the Browse Archetypes screen.
    func clearAll() async
}

// MARK: - Implementation

/// File-backed cache of "latest #1 finish per archetype" lookups.
///
/// Cache policy:
/// - **One file** holds the entire cache (`latest_top1.json`)
/// - **7-day TTL per entry** keyed by `<format>-<archetypeID>`
/// - **Lazy**: rows are fetched the first time the user views an
///   archetype. The Browse Archetypes screen runs hundreds of these
///   in parallel via `.task`, gated by SwiftUI's lazy stack so only
///   visible rows trigger network calls.
/// - **Persisted in-memory state** is loaded once on first access
///   and held in the actor for the rest of the session.
///
/// MTGTop8 has no API; we delegate to the existing
/// `MTGTop8Service.fetchLatestTop1` which returns the most recent
/// deck whose finish parses to placement 1.
actor LatestTopFinishesCache: LatestTopFinishesCacheProtocol {

    static let defaultTTL: TimeInterval = 7 * 24 * 60 * 60   // 7 days

    private let service: MTGTop8ServiceProtocol
    private let availabilityMonitor: MTGTop8AvailabilityMonitor
    private let cacheFile: URL
    private let ttl: TimeInterval

    /// In-memory mirror of the on-disk file. `nil` until first load.
    private var memoryCache: LatestTopFinishesCacheFile?

    init(
        service: MTGTop8ServiceProtocol = MTGTop8Service(),
        availabilityMonitor: MTGTop8AvailabilityMonitor = .shared,
        cacheDirectory: URL? = nil,
        ttl: TimeInterval = LatestTopFinishesCache.defaultTTL
    ) {
        self.service = service
        self.availabilityMonitor = availabilityMonitor
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
        self.cacheFile = directory.appendingPathComponent("latest_top1.json")
    }

    // MARK: - Public API

    func latestTop1(
        archetypeID: String,
        format: String,
        forceRefresh: Bool = false
    ) async -> MTGTop8Deck? {
        loadIfNeeded()
        let key = Self.cacheKey(format: format, archetypeID: archetypeID)
        let existingEntry = memoryCache?.entries[key]

        if !forceRefresh,
           let entry = existingEntry,
           !isStale(entry) {
            return entry.deck?.domain
        }

        // MTGTop8 currently unavailable — skip the network and serve
        // whatever we last cached (even if stale). Returns nil if the
        // archetype was never fetched at all.
        if await !availabilityMonitor.isAvailable {
            return existingEntry?.deck?.domain
        }

        // Cache miss or stale or forced — go to the network. Use throwing
        // form so a transient error falls back to the stale entry instead
        // of poisoning the cache with nil.
        let deck: MTGTop8Deck?
        do {
            deck = try await service.fetchLatestTop1(
                archetypeID: archetypeID,
                format: format
            )
        } catch {
            return existingEntry?.deck?.domain
        }

        var file = memoryCache ?? LatestTopFinishesCacheFile(entries: [:])
        file.entries[key] = LatestTopFinishesCacheEntry(
            fetchedAt: Date(),
            deck: deck.map(PersistedTopDeck.init)
        )
        memoryCache = file
        save()
        return deck
    }

    func clearAll() async {
        memoryCache = LatestTopFinishesCacheFile(entries: [:])
        save()
    }

    // MARK: - Cache I/O

    private static func cacheKey(format: String, archetypeID: String) -> String {
        "\(format)-\(archetypeID)"
    }

    private func loadIfNeeded() {
        if memoryCache != nil { return }
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            memoryCache = LatestTopFinishesCacheFile(entries: [:])
            return
        }
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            memoryCache = try decoder.decode(LatestTopFinishesCacheFile.self, from: data)
        } catch {
            // Corrupt file — start over rather than crashing.
            try? FileManager.default.removeItem(at: cacheFile)
            memoryCache = LatestTopFinishesCacheFile(entries: [:])
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
            // Best-effort persistence — don't crash on disk full / etc.
        }
    }

    private func isStale(_ entry: LatestTopFinishesCacheEntry) -> Bool {
        Date().timeIntervalSince(entry.fetchedAt) > ttl
    }
}
