import SwiftUI
import PhotosUI
import Photos

@Observable
@MainActor
final class BatchScanViewModel {
    let pipeline: CardIdentificationPipelineProtocol
    let cardRepository: CardRepositoryProtocol?
    let deckRepository: DeckListRepository?

    enum State: Equatable {
        case selecting
        case processing(current: Int, total: Int)
        case results
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.selecting, .selecting): return true
            case (.processing(let a, let b), .processing(let c, let d)): return a == c && b == d
            case (.results, .results): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    var state: State = .selecting
    var selectedPhotos: [PhotosPickerItem] = []
    var loadedImages: [CGImage] = []
    var identifiedCards: [BatchIdentifiedCard] = []
    /// Per-detection quantity (default 1). Keyed by index into `identifiedCards`.
    var quantities: [Int: Int] = [:]
    /// Per-detection cropped thumbnail (bbox-cropped from the source photo).
    /// Falls back to the full source image when bbox is missing/degenerate.
    /// Populated once at `applyBatchResult` so rows don't recompute on every render.
    var cardThumbnails: [Int: CGImage] = [:]
    /// Photo indices that produced zero recognized cards.
    var failedIndices: [Int] = []
    var analysis: String?
    var payloadBytes: Int = 0
    var addedToCollection: Int = 0
    var addedToDeck: DeckList?

    // Save-to-Photos state (mirrors ImageSplitterViewModel).
    var isSaving = false
    var savedCount: Int = 0
    var saveError: String?
    var saveSuccess = false
    var showSaveAlert = false

    init(pipeline: CardIdentificationPipelineProtocol,
         cardRepository: CardRepositoryProtocol? = nil,
         deckRepository: DeckListRepository? = nil) {
        self.pipeline = pipeline
        self.cardRepository = cardRepository
        self.deckRepository = deckRepository
    }

    /// Total card *instances* (sum of stepper quantities).
    var cardCount: Int {
        identifiedCards.indices.reduce(0) { $0 + quantity(at: $1) }
    }
    /// Distinct detections, before stepper multiplication.
    var detectionCount: Int { identifiedCards.count }
    /// Number of source photos that produced at least one card.
    var photosWithCards: Int { Set(identifiedCards.map(\.imageIndex)).count }
    var totalPhotos: Int { loadedImages.count }
    var payloadMB: String {
        ByteCountFormatter.string(fromByteCount: Int64(payloadBytes), countStyle: .file)
    }

    /// Sum of `Card.prices.usd × stepper quantity` across all detections.
    /// Cards without a USD price contribute 0; the result is never negative.
    /// Recomputes implicitly when `identifiedCards` or `quantities` change
    /// (e.g. after Fix → replaceCard swaps the printing).
    var totalValueUSD: Double {
        var total: Double = 0
        for (i, entry) in identifiedCards.enumerated() {
            guard let usd = entry.card.prices.usd, let value = Double(usd) else { continue }
            total += value * Double(quantity(at: i))
        }
        return total
    }

    /// True if at least one detection has a USD price. Used to decide whether
    /// to render the total at all — `$0.00` for a list of unpriced cards is
    /// noise.
    var hasAnyPrice: Bool {
        identifiedCards.contains { $0.card.prices.usd.flatMap(Double.init).map { $0 > 0 } ?? false }
    }

    func quantity(at index: Int) -> Int {
        quantities[index] ?? 1
    }

    func setQuantity(at index: Int, to value: Int) {
        quantities[index] = max(1, min(20, value))
    }

    func incrementQuantity(at index: Int) {
        setQuantity(at: index, to: quantity(at: index) + 1)
    }

    func decrementQuantity(at index: Int) {
        setQuantity(at: index, to: quantity(at: index) - 1)
    }

    /// Replaces the card at a detection index (used by the Fix → CardCorrectionView flow).
    func replaceCard(at index: Int, with card: Card) {
        guard index < identifiedCards.count else { return }
        let existing = identifiedCards[index]
        identifiedCards[index] = BatchIdentifiedCard(
            imageIndex: existing.imageIndex,
            card: card,
            boundingBox: existing.boundingBox
        )
        // Fix is an explicit user correction — feed it directly to the in-house scanner.
        if let crop = cardThumbnails[index], existing.boundingBox != nil {
            Task { await pipeline.learnFromIdentification(cardImage: crop, card: card) }
        }
    }

    func loadAndProcess() async {
        guard !selectedPhotos.isEmpty else { return }
        state = .processing(current: 0, total: selectedPhotos.count)

        // Decode via CGImageSource thumbnailing so the full-resolution RGBA
        // bitmap is never materialized. UIImage(data:).cgImage on a 48MP iPhone
        // photo decodes to ~195 MB, and three photos is enough for jetsam to
        // kill the app mid-load. The thumbnail path also bakes in EXIF rotation,
        // replacing the prior orientationNormalized() render pass.
        let processor = ImageProcessor()
        loadedImages = []
        for (i, item) in selectedPhotos.enumerated() {
            state = .processing(current: i + 1, total: selectedPhotos.count)
            if let data = try? await item.loadTransferable(type: Data.self),
               let cgImage = processor.downsample(data: data, maxDimension: 2048) {
                loadedImages.append(cgImage)
            }
        }

        guard !loadedImages.isEmpty else {
            state = .error("Could not load any photos")
            return
        }

        state = .processing(current: loadedImages.count, total: loadedImages.count)
        let result = await pipeline.identifyBatch(images: loadedImages)
        applyBatchResult(result)
    }

    /// Updates state from a pipeline result. Extracted for unit testing — bypasses
    /// the PhotosPicker loading step so tests can drive the post-API logic directly.
    func applyBatchResult(_ result: BatchIdentificationResult) {
        payloadBytes = result.payloadBytes
        analysis = result.analysis

        if let error = result.error {
            identifiedCards = []
            quantities = [:]
            cardThumbnails = [:]
            failedIndices = []
            state = .error(error)
            return
        }

        identifiedCards = result.cards
        quantities = Dictionary(uniqueKeysWithValues: identifiedCards.indices.map { ($0, 1) })
        cardThumbnails = computeThumbnails()
        let photosWithMatches = Set(identifiedCards.map(\.imageIndex))
        failedIndices = (0..<loadedImages.count).filter { !photosWithMatches.contains($0) }
        state = .results
    }

    /// Pre-computes a per-detection cropped CGImage so rows can render without
    /// running the crop on every redraw. Falls back to the full source photo
    /// when no usable bbox is available.
    private func computeThumbnails() -> [Int: CGImage] {
        var thumbs: [Int: CGImage] = [:]
        for (i, entry) in identifiedCards.enumerated() {
            guard entry.imageIndex < loadedImages.count else { continue }
            let source = loadedImages[entry.imageIndex]
            thumbs[i] = cropImage(source, withFractional: entry.boundingBox) ?? source
        }
        return thumbs
    }

    func addAllToCollection() {
        guard let repo = deckRepository else { return }
        var count = 0
        for (i, entry) in identifiedCards.enumerated() {
            for _ in 0..<quantity(at: i) {
                if (try? repo.addToCollection(card: entry.card)) != nil {
                    count += 1
                }
            }
        }
        addedToCollection = count
        Task { await learnIdentifiedCards() }
    }

    func createDeck(name: String) {
        guard let repo = deckRepository else { return }
        guard let deck = try? repo.createDeck(name: name) else { return }
        // Group by card name; sum stepper quantities.
        var grouped: [String: (card: Card, count: Int)] = [:]
        for (i, entry) in identifiedCards.enumerated() {
            let qty = quantity(at: i)
            if var existing = grouped[entry.card.name] {
                existing.count += qty
                grouped[entry.card.name] = existing
            } else {
                grouped[entry.card.name] = (card: entry.card, count: qty)
            }
        }
        for (_, entry) in grouped {
            _ = try? repo.addItem(card: entry.card, quantity: entry.count, to: deck)
        }
        addedToDeck = deck
        Task { await learnIdentifiedCards() }
    }

    /// Feeds confirmed batch identifications back into the in-house scanner's
    /// embedding store. Only runs when there's a real bbox crop — using the full
    /// source photo as a training sample would be too noisy. Triggered on user
    /// confirmation (Add to Collection / Create Deck), not on raw Gemini output,
    /// because Gemini's per-card set/collector accuracy is imperfect and the
    /// user has reviewed the list (and used Fix where needed) before tapping.
    func learnIdentifiedCards() async {
        for (i, entry) in identifiedCards.enumerated() {
            // Skip when there's no real crop (full-photo fallback isn't useful training data).
            guard entry.boundingBox != nil,
                  let crop = cardThumbnails[i] else { continue }
            await pipeline.learnFromIdentification(cardImage: crop, card: entry.card)
        }
    }

    // MARK: - Save to Photos

    /// Crops each identified detection out of its source photo using the Gemini bbox
    /// and saves the crops to the user's Photo library. Falls back to the full source
    /// photo when no bbox is available.
    func saveCardsToPhotos() async {
        isSaving = true
        saveError = nil
        saveSuccess = false
        savedCount = 0

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveError = "Photo library access denied. Enable in Settings."
            isSaving = false
            return
        }

        let crops = buildCropsForSaving()
        guard !crops.isEmpty else {
            saveError = "No cards to save"
            isSaving = false
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for crop in crops {
                    PHAssetChangeRequest.creationRequestForAsset(from: UIImage(cgImage: crop))
                }
            }
            savedCount = crops.count
            saveSuccess = true
            showSaveAlert = true
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// Internal helper exposed for unit testing. Returns the crops that would be saved.
    /// One crop per *instance* (stepper quantity expanded), so a 3× detection contributes
    /// three identical crops.
    func buildCropsForSaving() -> [CGImage] {
        var crops: [CGImage] = []
        for (i, entry) in identifiedCards.enumerated() {
            guard entry.imageIndex < loadedImages.count else { continue }
            let source = loadedImages[entry.imageIndex]
            let crop = cropImage(source, withFractional: entry.boundingBox) ?? source
            for _ in 0..<quantity(at: i) {
                crops.append(crop)
            }
        }
        return crops
    }

    /// Crops `source` using fractional (0–1) coordinates. Returns nil if the bbox is
    /// missing, degenerate, or produces a sub-50px crop (likely a Gemini hallucination).
    private func cropImage(_ source: CGImage, withFractional bbox: BatchBoundingBox?) -> CGImage? {
        guard let bbox else { return nil }
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        let rect = CGRect(
            x: max(0, bbox.x * width),
            y: max(0, bbox.y * height),
            width: min(width, bbox.w * width),
            height: min(height, bbox.h * height)
        )
        guard rect.width >= 50, rect.height >= 50 else { return nil }
        return source.cropping(to: rect)
    }

    func reset() {
        state = .selecting
        selectedPhotos = []
        loadedImages = []
        identifiedCards = []
        quantities = [:]
        cardThumbnails = [:]
        failedIndices = []
        analysis = nil
        payloadBytes = 0
        addedToCollection = 0
        addedToDeck = nil
        isSaving = false
        savedCount = 0
        saveError = nil
        saveSuccess = false
        showSaveAlert = false
    }
}
