import Foundation
import CoreGraphics

/// A visual search index entry mapping an illustration to its pHash.
struct VisualIndexEntry: Codable, Sendable {
    let illustrationID: String
    let cardName: String
    let hash: UInt64
}

/// Loads a pre-computed pHash index and performs visual card identification.
struct VisualSearchEngine: Sendable {

    private let index: [VisualIndexEntry]

    /// Creates an engine from a loaded index.
    init(index: [VisualIndexEntry]) {
        self.index = index
    }

    /// Loads the index from a JSON file in the app bundle.
    static func loadFromBundle(filename: String = "visual_index") -> VisualSearchEngine? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([VisualIndexEntry].self, from: data) else {
            return nil
        }
        return VisualSearchEngine(index: entries)
    }

    /// Loads the index from a file URL (e.g., in Application Support).
    static func load(from url: URL) -> VisualSearchEngine? {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([VisualIndexEntry].self, from: data) else {
            return nil
        }
        return VisualSearchEngine(index: entries)
    }

    /// Finds the best matching card art for the given image.
    /// Returns the top matches sorted by similarity (lowest Hamming distance first).
    func findMatches(for image: CGImage, maxResults: Int = 5) -> [(entry: VisualIndexEntry, distance: Int)] {
        guard let queryHash = PerceptualHash.compute(from: image) else { return [] }

        var results: [(entry: VisualIndexEntry, distance: Int)] = []

        for entry in index {
            let distance = PerceptualHash.hammingDistance(queryHash, entry.hash)
            results.append((entry, distance))
        }

        results.sort { $0.distance < $1.distance }
        return Array(results.prefix(maxResults))
    }

    /// Finds the single best match. Returns nil if no close match (distance > threshold).
    func bestMatch(for image: CGImage, maxDistance: Int = 15) -> VisualIndexEntry? {
        let matches = findMatches(for: image, maxResults: 1)
        guard let best = matches.first, best.distance <= maxDistance else { return nil }
        return best.entry
    }

    /// The number of entries in the index.
    var count: Int { index.count }
}
