import Foundation
import CoreGraphics
import Vision

/// A cached VNFeaturePrint entry for a card art illustration.
struct FeaturePrintCacheEntry: Codable, Sendable {
    let illustrationID: String
    let cardName: String
    let featurePrintData: Data  // NSKeyedArchiver-encoded VNFeaturePrintObservation
}

/// Caches VNFeaturePrint observations for identified card art.
/// Grows organically as the user scans cards — repeat cards identify instantly.
actor FeaturePrintCache {
    private var entries: [FeaturePrintCacheEntry] = []
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.entries = Self.loadEntries(from: fileURL)
    }

    /// Searches the cache for a matching art image.
    /// Returns the card name and illustration ID if a match is found within threshold.
    func search(artImage: CGImage, maxDistance: Float = 7.0) -> (illustrationID: String, cardName: String)? {
        // Generate feature print for the query art
        guard let queryPrint = generateFeaturePrint(for: artImage) else { return nil }

        var bestMatch: (illustrationID: String, cardName: String)?
        var bestDistance: Float = Float.greatestFiniteMagnitude

        for entry in entries {
            guard let cachedPrint = deserializeFeaturePrint(entry.featurePrintData) else { continue }

            var distance: Float = 0
            do {
                try queryPrint.computeDistance(&distance, to: cachedPrint)
                if distance < bestDistance && distance <= maxDistance {
                    bestDistance = distance
                    bestMatch = (entry.illustrationID, entry.cardName)
                }
            } catch { continue }
        }

        if let match = bestMatch {
            print("[MTGScanner] FeaturePrint cache hit: '\(match.cardName)' (distance: \(String(format: "%.2f", bestDistance)))")
        }

        return bestMatch
    }

    /// Adds a new entry to the cache after successful identification.
    func cache(illustrationID: String, cardName: String, artImage: CGImage) {
        // Don't cache duplicates
        guard !entries.contains(where: { $0.illustrationID == illustrationID }) else { return }

        guard let featurePrint = generateFeaturePrint(for: artImage) else { return }
        guard let data = serializeFeaturePrint(featurePrint) else { return }

        entries.append(FeaturePrintCacheEntry(
            illustrationID: illustrationID,
            cardName: cardName,
            featurePrintData: data
        ))

        print("[MTGScanner] Cached VNFeaturePrint for '\(cardName)' (\(entries.count) total)")
    }

    /// Adds or updates a cache entry for the given illustration ID.
    /// Unlike `cache()`, this replaces an existing entry if one exists
    /// with the same illustration ID. Used by the correction flow to
    /// override incorrect cached identifications.
    func cacheOrUpdate(illustrationID: String, cardName: String, artImage: CGImage) {
        guard let featurePrint = generateFeaturePrint(for: artImage) else { return }
        guard let data = serializeFeaturePrint(featurePrint) else { return }

        // Remove any existing entry for this illustration ID
        entries.removeAll { $0.illustrationID == illustrationID }

        entries.append(FeaturePrintCacheEntry(
            illustrationID: illustrationID,
            cardName: cardName,
            featurePrintData: data
        ))

        print("[MTGScanner] Cache updated for '\(cardName)' (\(entries.count) total)")
    }

    /// Persists the cache to disk.
    func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL)
    }

    var count: Int { entries.count }

    // MARK: - Private

    private static func loadEntries(from url: URL) -> [FeaturePrintCacheEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([FeaturePrintCacheEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func generateFeaturePrint(for image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    private func serializeFeaturePrint(_ observation: VNFeaturePrintObservation) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    private func deserializeFeaturePrint(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }
}
