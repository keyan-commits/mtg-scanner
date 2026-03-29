import Foundation
import SwiftData

// MARK: - Database Manager

@MainActor
final class DatabaseManager: Sendable {
    let modelContainer: ModelContainer

    init(inMemory: Bool = false) throws {
        let schema = Schema([CardRecord.self])
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
}
