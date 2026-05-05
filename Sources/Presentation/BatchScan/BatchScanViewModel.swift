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
    /// Per-detection foil state. Keyed by index. Defaults to true when the
    /// printing exists only in foil (FNM, Secret Lair foil drops, etc.) so
    /// the row immediately reflects reality, otherwise false.
    var foilFlags: [Int: Bool] = [:]
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

    /// Sum of unit-price × stepper quantity across all detections, where
    /// "unit price" is the foil price when the row is marked foil and
    /// the nonfoil price otherwise (falling back to whichever exists if
    /// the preferred one is missing). Cards without any USD price
    /// contribute 0; the result is never negative.
    var totalValueUSD: Double {
        var total: Double = 0
        for i in identifiedCards.indices {
            if let value = unitPriceUSD(at: i) {
                total += value * Double(quantity(at: i))
            }
        }
        return total
    }

    /// True if at least one detection has any USD price (foil or nonfoil).
    /// Used to decide whether to render the total at all — `$0.00` for a
    /// list of unpriced cards is noise.
    var hasAnyPrice: Bool {
        for entry in identifiedCards {
            let nonfoil = Double(entry.card.prices.usd ?? "") ?? 0
            let foil = Double(entry.card.prices.usdFoil ?? "") ?? 0
            if nonfoil > 0 || foil > 0 { return true }
        }
        return false
    }

    /// Whether the row at `index` is currently treated as foil. Foil-only
    /// printings (FNM, Secret Lair foil drops) auto-default to true and
    /// the UI should lock the toggle off — there's no nonfoil version
    /// to switch to.
    func isFoil(at index: Int) -> Bool {
        if let explicit = foilFlags[index] { return explicit }
        return foilOnly(at: index)
    }

    /// True when the printing has no nonfoil variant. The foil toggle
    /// should be disabled (always on) for these.
    func foilOnly(at index: Int) -> Bool {
        guard index < identifiedCards.count else { return false }
        return identifiedCards[index].card.isFoilOnly
    }

    func setFoil(at index: Int, to value: Bool) {
        // Foil-only printings can't be set to nonfoil — silently coerce
        // to true so callers don't need a separate guard.
        foilFlags[index] = foilOnly(at: index) ? true : value
    }

    func toggleFoil(at index: Int) {
        setFoil(at: index, to: !isFoil(at: index))
    }

    /// Per-row USD unit price honoring the current foil flag. Returns nil
    /// when neither nonfoil nor foil is priced.
    func unitPriceUSD(at index: Int) -> Double? {
        guard index < identifiedCards.count else { return nil }
        let prices = identifiedCards[index].card.prices
        let nonfoil = prices.usd.flatMap(Double.init)
        let foil = prices.usdFoil.flatMap(Double.init)
        if isFoil(at: index) {
            return foil ?? nonfoil
        }
        return nonfoil ?? foil
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
        // If the new printing is foil-only, force the foil flag on.
        // Otherwise preserve the user's prior choice.
        if card.isFoilOnly { foilFlags[index] = true }
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
        // Seed foil flags: foil-only printings auto-true; everything else
        // stays nil so `isFoil(at:)` returns false until the user toggles.
        foilFlags = [:]
        for i in identifiedCards.indices where identifiedCards[i].card.isFoilOnly {
            foilFlags[i] = true
        }
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
            let qty = quantity(at: i)
            // CollectionItem.quantity is TOTAL copies (foil + nonfoil
            // combined); foilQuantity is the subset that's foil.
            // Invariant: foilQuantity ≤ quantity. Always pass the full
            // qty as `quantity` and the foil subset separately.
            let foilQty = isFoil(at: i) ? qty : 0
            if (try? repo.addToCollection(
                card: entry.card,
                quantity: qty,
                foilQuantity: foilQty
            )) != nil {
                count += qty
            }
        }
        addedToCollection = count
        Task { await learnIdentifiedCards() }
    }

    func createDeck(name: String) {
        guard let repo = deckRepository else { return }
        guard let deck = try? repo.createDeck(name: name) else { return }
        // Group by (card name, foil flag) — foil and nonfoil copies of the
        // same card are different products in a deck context.
        struct Key: Hashable { let name: String; let isFoil: Bool }
        var grouped: [Key: (card: Card, count: Int)] = [:]
        for (i, entry) in identifiedCards.enumerated() {
            let qty = quantity(at: i)
            let key = Key(name: entry.card.name, isFoil: isFoil(at: i))
            if var existing = grouped[key] {
                existing.count += qty
                grouped[key] = existing
            } else {
                grouped[key] = (card: entry.card, count: qty)
            }
        }
        for (key, entry) in grouped {
            _ = try? repo.addItem(
                card: entry.card,
                quantity: entry.count,
                to: deck,
                isFoil: key.isFoil
            )
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
