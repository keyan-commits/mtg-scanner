import Foundation
import SwiftData

// MARK: - Database Manager

@MainActor
final class DatabaseManager: Sendable {
    let modelContainer: ModelContainer

    init(inMemory: Bool = false) throws {
        let schema = Schema([CardRecord.self, DeckList.self, PurchaseItem.self, Order.self, CollectionItem.self, CardAnalysis.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        self.modelContainer = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    // MARK: - Bulk Import

    func importBulkData(from fileURL: URL) async throws {
        let data = try Data(contentsOf: fileURL)
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw BulkDataError.invalidResponse
        }

        let context = ModelContext(modelContainer)
        let batchSize = 500
        var count = 0

        for json in jsonArray {
            guard let record = CardRecord.fromBulkJSON(json) else { continue }
            context.insert(record)
            count += 1

            if count % batchSize == 0 {
                try context.save()
            }
        }

        // Save any remaining records
        if count % batchSize != 0 {
            try context.save()
        }
    }

    // MARK: - Search

    func searchCards(name: String) async throws -> [CardRecord] {
        let context = ModelContext(modelContainer)
        let lowercasedName = name.lowercased()
        let descriptor = FetchDescriptor<CardRecord>(
            predicate: #Predicate<CardRecord> { record in
                record.name.localizedStandardContains(lowercasedName)
            }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Find All Printings by Name

    func findCards(name: String) async throws -> [CardRecord] {
        let context = ModelContext(modelContainer)
        let lowercasedName = name.lowercased()
        let descriptor = FetchDescriptor<CardRecord>(
            predicate: #Predicate<CardRecord> { record in
                record.name.localizedStandardContains(lowercasedName)
            }
        )
        let results = try context.fetch(descriptor)
        // Return exact name matches only (filter out partial matches)
        return results.filter { $0.name.lowercased() == lowercasedName }
    }

    // MARK: - Fuzzy match by name

    /// Per-process memoization for `findFuzzyMatch`. Fuzzy lookups
    /// are expensive (Levenshtein over the entire catalog) so we
    /// cache positive AND negative results in-process. Repeated
    /// misses for the same misspelled name (e.g. when a deck list
    /// re-renders) are instant after the first hit.
    nonisolated(unsafe) private static var fuzzyCache: [String: ScryfallID] = [:]
    nonisolated(unsafe) private static let fuzzyCacheLock = NSLock()
    private typealias ScryfallID = String

    private static func cachedFuzzyMatch(for query: String) -> ScryfallID?? {
        fuzzyCacheLock.lock()
        defer { fuzzyCacheLock.unlock() }
        // Outer optional: did we look this up before?
        // Inner optional: was the lookup successful?
        if let entry = fuzzyCache[query] {
            return .some(.some(entry))
        }
        if fuzzyCache.keys.contains(query) {
            return .some(.none)
        }
        return .none
    }

    private static func storeFuzzyMatch(query: String, scryfallID: ScryfallID?) {
        fuzzyCacheLock.lock()
        defer { fuzzyCacheLock.unlock() }
        if let scryfallID {
            fuzzyCache[query] = scryfallID
        } else {
            // Store negative result by mapping to empty string sentinel
            fuzzyCache[query] = ""
        }
    }

    /// Best-effort typo-tolerant name lookup. Walks all card records,
    /// computes Levenshtein distance against `query`, returns the
    /// closest match if it's "close enough" (≤25% of the longer
    /// string's length, capped at distance 4).
    ///
    /// Used as a final fallback by `CardResolver` when exact, DFC,
    /// and reverse-DFC lookups all miss — typically because the
    /// upstream data source (MTGTop8 transcription) has a typo
    /// like "Loerien Revield" → "Lórien Revealed".
    ///
    /// Cost is bounded by length filtering: only candidates whose
    /// name length is within ±5 of the query are scored, which
    /// drops most of the 50K-card catalog before the inner loop.
    /// Typical run is well under 100ms even for cold queries.
    func findFuzzyMatch(name query: String) async throws -> CardRecord? {
        let normalizedQuery = Self.normalizeForFuzzy(query)
        guard normalizedQuery.count >= 4 else { return nil }
        let queryLen = normalizedQuery.count

        // Memoization: positive AND negative results cached.
        // Repeated misses for the same misspelled name are instant.
        if let cached = Self.cachedFuzzyMatch(for: normalizedQuery) {
            switch cached {
            case .some(let scryfallID) where !scryfallID.isEmpty:
                let context = ModelContext(modelContainer)
                let descriptor = FetchDescriptor<CardRecord>(
                    predicate: #Predicate<CardRecord> { $0.scryfallID == scryfallID }
                )
                return try? context.fetch(descriptor).first
            default:
                return nil  // negative cache hit
            }
        }

        let context = ModelContext(modelContainer)
        // Pull all records — we filter by length in-memory because
        // SwiftData predicates can't express `name.count BETWEEN`.
        let all = try context.fetch(FetchDescriptor<CardRecord>())

        var best: (record: CardRecord, distance: Int)?
        let maxAcceptableDistance = min(4, queryLen / 4)

        for record in all {
            let candidate = Self.normalizeForFuzzy(record.name)
            // Length pre-filter: skip wildly different lengths
            let lenDiff = abs(candidate.count - queryLen)
            if lenDiff > maxAcceptableDistance { continue }

            let distance = Self.levenshtein(normalizedQuery, candidate, ceiling: maxAcceptableDistance)
            if distance <= maxAcceptableDistance,
               best == nil || distance < best!.distance {
                best = (record, distance)
                if distance == 0 { break }
            }
        }

        Self.storeFuzzyMatch(query: normalizedQuery, scryfallID: best?.record.scryfallID)
        return best?.record
    }

    /// Lowercase + ASCII-fold (strips diacritics) so "Lórien" matches
    /// the user typing "Lorien".
    private static func normalizeForFuzzy(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Iterative Levenshtein with early termination once `ceiling` is
    /// exceeded — saves work on long mismatched names.
    private static func levenshtein(_ a: String, _ b: String, ceiling: Int) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        if abs(m - n) > ceiling { return ceiling + 1 }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,        // deletion
                    curr[j - 1] + 1,    // insertion
                    prev[j - 1] + cost  // substitution
                )
                if curr[j] < rowMin { rowMin = curr[j] }
            }
            // Early exit: if every cell in this row already exceeds
            // the ceiling, the final distance can't be lower.
            if rowMin > ceiling { return ceiling + 1 }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    // MARK: - Find by Name + Artist

    func findCards(name: String, artist: String) async throws -> [CardRecord] {
        let allPrintings = try await findCards(name: name)
        let lowerArtist = artist.lowercased()
        return allPrintings.filter { record in
            guard let recordArtist = record.artist else { return false }
            return recordArtist.lowercased().contains(lowerArtist)
                || lowerArtist.contains(recordArtist.lowercased())
        }
    }

    // MARK: - Find by Name + Printing Attributes

    func findCards(name: String, artist: String?, releasedYear: Int?, borderColor: String?) async throws -> [CardRecord] {
        var results = try await findCards(name: name)

        if let artist = artist {
            let lowerArtist = artist.lowercased()
            results = results.filter { record in
                guard let recordArtist = record.artist else { return false }
                return recordArtist.lowercased().contains(lowerArtist)
                    || lowerArtist.contains(recordArtist.lowercased())
            }
        }

        if let releasedYear = releasedYear {
            let yearString = String(releasedYear)
            results = results.filter { record in
                guard let releasedAt = record.releasedAt, releasedAt.count >= 4 else { return false }
                return String(releasedAt.prefix(4)) == yearString
            }
        }

        if let borderColor = borderColor {
            results = results.filter { record in
                record.borderColor == borderColor
            }
        }

        return results
    }

    // MARK: - Find (Exact Match, Single)

    func findCard(name: String) async throws -> CardRecord? {
        let context = ModelContext(modelContainer)
        let lowercasedName = name.lowercased()
        let descriptor = FetchDescriptor<CardRecord>(
            predicate: #Predicate<CardRecord> { record in
                record.name.localizedStandardContains(lowercasedName)
            }
        )
        let results = try context.fetch(descriptor)
        // Prefer exact case-insensitive match over partial matches
        return results.first { $0.name.lowercased() == lowercasedName } ?? results.first
    }

    // MARK: - Find by Scryfall ID

    func findCard(scryfallID: String) async throws -> CardRecord? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CardRecord>(
            predicate: #Predicate<CardRecord> { record in
                record.scryfallID == scryfallID
            }
        )
        let results = try context.fetch(descriptor)
        return results.first
    }

    // MARK: - Find by Set + Collector Number

    func findCard(setCode: String, collectorNumber: String) async throws -> CardRecord? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CardRecord>(
            predicate: #Predicate<CardRecord> { record in
                record.setCode == setCode && record.collectorNumber == collectorNumber
            }
        )
        let results = try context.fetch(descriptor)
        return results.first
    }

    // MARK: - Find Variants (Same Name + Set)

    func findVariants(name: String, setCode: String) async throws -> [CardRecord] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CardRecord>(
            predicate: #Predicate<CardRecord> { record in
                record.name == name && record.setCode == setCode
            }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Find by Illustration ID

    func findByIllustrationID(_ illustrationID: String) async throws -> [CardRecord] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CardRecord>(
            predicate: #Predicate<CardRecord> { record in
                record.illustrationID == illustrationID
            }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Count

    func cardCount() async throws -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CardRecord>()
        return try context.fetchCount(descriptor)
    }

    // MARK: - Sets & Top Cards

    /// Returns distinct sets from the database as (code, name, setType, releasedAt) tuples.
    /// Deduplicates by set code and picks the first record's metadata for each set.
    func fetchDistinctSets() async throws -> [(code: String, name: String, setType: String, releasedAt: String?)] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CardRecord>()
        let records = try context.fetch(descriptor)

        var seen = Set<String>()
        var sets: [(code: String, name: String, setType: String, releasedAt: String?)] = []
        for record in records {
            guard !seen.contains(record.setCode) else { continue }
            seen.insert(record.setCode)
            sets.append((record.setCode, record.setName, record.setType, record.releasedAt))
        }
        return sets
    }

    /// Returns all basic lands from the database.
    func fetchBasicLands() async throws -> [CardRecord] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CardRecord>(
            predicate: #Predicate<CardRecord> { record in
                record.typeLine.contains("Basic Land")
            }
        )
        return try context.fetch(descriptor)
    }

    /// Returns all cards in a given set.
    func fetchCards(setCode code: String) async throws -> [CardRecord] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CardRecord>(
            predicate: #Predicate<CardRecord> { record in
                record.setCode == code
            }
        )
        return try context.fetch(descriptor)
    }
}
