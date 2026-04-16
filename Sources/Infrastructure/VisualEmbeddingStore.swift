import Foundation
import CoreGraphics
import Vision

/// Persistent k-NN classifier using VNFeaturePrint embeddings.
/// Learns from user corrections — each correction adds a training point
/// that permanently improves future card identification.
///
/// Unlike the volatile FeaturePrint cache, this:
/// - Persists across app sessions (saved to disk)
/// - Accumulates corrections over time
/// - Generalizes across different photos of the same card
/// - Is NEVER cleared between batch scans (the FP cache is)
actor VisualEmbeddingStore {

    struct Embedding: Codable {
        let cardName: String
        let setCode: String
        let collectorNumber: String
        let featurePrintData: Data  // NSKeyedArchiver-encoded VNFeaturePrintObservation
        let addedAt: Date
        let isCorrection: Bool  // Corrections have higher trust than auto-learned samples

        init(cardName: String, setCode: String, collectorNumber: String, featurePrintData: Data, addedAt: Date, isCorrection: Bool = false) {
            self.cardName = cardName
            self.setCode = setCode
            self.collectorNumber = collectorNumber
            self.featurePrintData = featurePrintData
            self.addedAt = addedAt
            self.isCorrection = isCorrection
        }
    }

    private var embeddings: [Embedding] = []
    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("visual_embeddings.json")
        // Load synchronously from the file during init
        if let data = try? Data(contentsOf: docs.appendingPathComponent("visual_embeddings.json")),
           let decoded = try? JSONDecoder().decode([Embedding].self, from: data) {
            embeddings = decoded
            print("[VisualEmbeddingStore] Loaded \(embeddings.count) user embeddings")
        }
        loadBaseEmbeddings()
    }

    /// Number of stored embeddings (training points).
    var count: Int { embeddings.count }

    /// Number of distinct card names in the store.
    var uniqueCardCount: Int {
        Set(embeddings.map(\.cardName)).count
    }

    /// Total number of embedding samples stored.
    var totalSampleCount: Int { embeddings.count }

    /// Maximum number of user embeddings to keep. When exceeded, oldest non-correction samples are pruned.
    /// Base embeddings from the app bundle do not count toward this cap.
    private static let maxUserEmbeddings = 5000

    /// Number of base embeddings loaded from the bundle (not counted toward user cap).
    private var baseEmbeddingCount = 0

    /// Adds a correction: saves the card crop's embedding with the correct card name.
    /// Corrections have higher trust and are never pruned by the size cap.
    func addCorrection(cardImage: CGImage, cardName: String, setCode: String, collectorNumber: String) async {
        guard let featurePrint = generateFeaturePrint(for: cardImage),
              let data = serializeFeaturePrint(featurePrint) else { return }

        // Deduplication: skip if a very similar embedding already exists for this card
        if isDuplicate(featurePrint: featurePrint, cardName: cardName) { return }

        let embedding = Embedding(
            cardName: cardName,
            setCode: setCode,
            collectorNumber: collectorNumber,
            featurePrintData: data,
            addedAt: Date(),
            isCorrection: true
        )
        embeddings.append(embedding)
        enforceCapacity()
        save()
    }

    /// Adds a sample from a successful identification (passive learning).
    /// Lower trust than corrections — these are pruned first when the store is full.
    func addSample(cardImage: CGImage, cardName: String, setCode: String, collectorNumber: String) async {
        guard let featurePrint = generateFeaturePrint(for: cardImage),
              let data = serializeFeaturePrint(featurePrint) else { return }

        // Deduplication: skip if a very similar embedding already exists for this card
        if isDuplicate(featurePrint: featurePrint, cardName: cardName) { return }

        let embedding = Embedding(
            cardName: cardName,
            setCode: setCode,
            collectorNumber: collectorNumber,
            featurePrintData: data,
            addedAt: Date(),
            isCorrection: false
        )
        embeddings.append(embedding)
        enforceCapacity()
        save()
    }

    /// Finds the best match for a card image using k=3 majority vote.
    /// Returns the card name and distance, or nil if no match is close enough.
    func findMatch(for cardImage: CGImage, maxDistance: Float = 12.0) async -> (cardName: String, setCode: String, collectorNumber: String, distance: Float)? {
        guard !embeddings.isEmpty else { return nil }
        guard let queryPrint = generateFeaturePrint(for: cardImage) else { return nil }

        // Compute distances to all embeddings
        var scored: [(embedding: Embedding, distance: Float)] = []
        for embedding in embeddings {
            guard let cachedPrint = deserializeFeaturePrint(embedding.featurePrintData) else { continue }
            var distance: Float = 0
            do {
                try queryPrint.computeDistance(&distance, to: cachedPrint)
                scored.append((embedding, distance))
            } catch { continue }
        }

        guard !scored.isEmpty else { return nil }

        // Sort by distance and take top-k (k=3)
        scored.sort { $0.distance < $1.distance }
        let k = min(3, scored.count)
        let topK = Array(scored.prefix(k))

        // Check if closest is within max distance
        guard topK[0].distance <= maxDistance else { return nil }

        if k >= 2 {
            // k-NN majority vote: count how many of the top-k agree on each card name
            var votes: [String: (count: Int, bestEntry: (embedding: Embedding, distance: Float))] = [:]
            for entry in topK {
                let name = entry.embedding.cardName
                if let existing = votes[name] {
                    votes[name] = (existing.count + 1, existing.bestEntry.distance < entry.distance ? existing.bestEntry : entry)
                } else {
                    votes[name] = (1, entry)
                }
            }

            // Find the name with the most votes
            let best = votes.max(by: { a, b in
                if a.value.count != b.value.count { return a.value.count < b.value.count }
                return a.value.bestEntry.distance > b.value.bestEntry.distance
            })!

            if best.value.count >= 2 {
                // 2+ of 3 agree — high confidence
                let match = best.value.bestEntry
                print("[VisualEmbeddingStore] k-NN vote: '\(match.embedding.cardName)' (\(best.value.count)/\(k) agree, distance: \(String(format: "%.2f", match.distance)))")
                return (match.embedding.cardName, match.embedding.setCode, match.embedding.collectorNumber, match.distance)
            } else {
                // All 3 disagree — use closest only if very strict distance
                let closest = topK[0]
                guard closest.distance < 8.0 else { return nil }
                print("[VisualEmbeddingStore] k-NN no consensus, using closest: '\(closest.embedding.cardName)' (distance: \(String(format: "%.2f", closest.distance)))")
                return (closest.embedding.cardName, closest.embedding.setCode, closest.embedding.collectorNumber, closest.distance)
            }
        } else {
            // Only 1 embedding — fall back to simple nearest neighbor
            let match = topK[0]
            print("[VisualEmbeddingStore] Match: '\(match.embedding.cardName)' (distance: \(String(format: "%.2f", match.distance)))")
            return (match.embedding.cardName, match.embedding.setCode, match.embedding.collectorNumber, match.distance)
        }
    }

    /// Clears all stored embeddings.
    func clear() {
        embeddings = []
        save()
    }

    // MARK: - Private

    /// Checks if a very similar embedding already exists for the same card (deduplication).
    /// Returns true if a duplicate is found (distance < 3.0), meaning we should skip adding.
    private func isDuplicate(featurePrint: VNFeaturePrintObservation, cardName: String) -> Bool {
        for embedding in embeddings where embedding.cardName == cardName {
            guard let cachedPrint = deserializeFeaturePrint(embedding.featurePrintData) else { continue }
            var distance: Float = 0
            do {
                try featurePrint.computeDistance(&distance, to: cachedPrint)
                if distance < 3.0 {
                    print("[VisualEmbeddingStore] Skipping duplicate for '\(cardName)' (distance: \(String(format: "%.2f", distance)))")
                    return true
                }
            } catch { continue }
        }
        return false
    }

    /// Enforces the size cap by removing oldest non-correction samples when over limit.
    /// Base embeddings (loaded from bundle) don't count toward the user cap.
    private func enforceCapacity() {
        let userCount = embeddings.count - baseEmbeddingCount
        guard userCount > Self.maxUserEmbeddings else { return }
        // Sort non-correction samples by date (oldest first) and remove enough to get under cap
        let excess = userCount - Self.maxUserEmbeddings
        var removedCount = 0
        var indicesToRemove: [Int] = []

        // Collect indices of non-correction samples, oldest first
        let sortedIndices = embeddings.indices
            .filter { !embeddings[$0].isCorrection }
            .sorted { embeddings[$0].addedAt < embeddings[$1].addedAt }

        for idx in sortedIndices {
            guard removedCount < excess else { break }
            indicesToRemove.append(idx)
            removedCount += 1
        }

        // Remove in reverse order to keep indices valid
        for idx in indicesToRemove.sorted().reversed() {
            embeddings.remove(at: idx)
        }

        if removedCount > 0 {
            print("[VisualEmbeddingStore] Pruned \(removedCount) oldest samples to stay under \(Self.maxUserEmbeddings) user cap")
        }
    }

    /// Loads pre-computed base embeddings from the app bundle.
    /// Base embeddings provide out-of-the-box visual matching without requiring user corrections.
    /// User corrections take priority over base embeddings for the same card.
    private func loadBaseEmbeddings() {
        // Try bundle first (development builds with file included)
        let bundleURL = Bundle.main.url(forResource: "base_embeddings", withExtension: "json")
        // Try Documents/ (downloaded on first launch via EmbeddingDownloader)
        let docsURL = EmbeddingDownloader.embeddingsDocumentsURL

        guard let url = bundleURL ?? (FileManager.default.fileExists(atPath: docsURL.path) ? docsURL : nil),
              let data = try? Data(contentsOf: url),
              let base = try? JSONDecoder().decode([Embedding].self, from: data) else {
            print("[VisualEmbeddingStore] No base embeddings found in bundle or Documents")
            return
        }

        // Merge: add base embeddings that don't conflict with user corrections
        let userCorrectedCards = Set(embeddings.filter(\.isCorrection).map { $0.cardName.lowercased() })
        let newBase = base.filter { !userCorrectedCards.contains($0.cardName.lowercased()) }
        embeddings.append(contentsOf: newBase)
        baseEmbeddingCount = newBase.count
        print("[VisualEmbeddingStore] Loaded \(newBase.count) base embeddings (skipped \(base.count - newBase.count) overridden by user corrections)")
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

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Embedding].self, from: data) else { return }
        embeddings = decoded
        print("[VisualEmbeddingStore] Loaded \(embeddings.count) embeddings")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(embeddings) else { return }
        try? data.write(to: fileURL)
        print("[VisualEmbeddingStore] Saved \(embeddings.count) embeddings")
    }
}
