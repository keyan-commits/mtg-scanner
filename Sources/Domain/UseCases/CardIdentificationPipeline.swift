import Foundation
import CoreGraphics
import CoreImage
import Vision

// MARK: - Card Identification Pipeline
//
// ┌─────────────────────────────────────────────────────────────────┐
// │                  CARD IDENTIFICATION PIPELINE                   │
// │                                                                 │
// │  This is the core identification engine. It takes raw image     │
// │  data and returns the exact Card printing, including set,       │
// │  collector number, and art variant.                             │
// │                                                                 │
// │  PIPELINE STEPS:                                                │
// │                                                                 │
// │  Step 0: Image Preparation                                     │
// │    - Downsample raw image data for memory efficiency            │
// │    - Detect card rectangle via VNDetectRectanglesRequest        │
// │    - Perspective-correct and crop to card bounds                │
// │                                                                 │
// │  Step 1: Visual Search (primary — vision-first approach)        │
// │    - Extract art region from cropped card image                 │
// │    - Query VisualSearchEngine for perceptual hash match         │
// │    - If match found: card name + illustration_id known          │
// │    - Use OCR signals to narrow to exact printing                │
// │    - Skipped if visual index not available                      │
// │                                                                 │
// │  Step 2: OCR Fallback (when visual search unavailable/fails)    │
// │    - Card name (topmost text via CardNameExtractor)             │
// │    - Collector number + set code (bottom text)                  │
// │    - Artist name (from "Illus." line)                           │
// │    - Copyright end year (from "©YYYY" or "©YYYY-YYYY")         │
// │    - Old frame detection ("Summon" type line = pre-1999)        │
// │    - Border color (pixel sampling on cropped card)              │
// │                                                                 │
// │  Step 3: Printing Resolution (most precise first)               │
// │    3a. Set code + collector number → exact printing             │
// │    3b. Collector number only → match among all printings        │
// │    3c. Metadata filtering: artist → year → frame → border      │
// │    3d. Printing priority sort (expansion > core > promo)        │
// │    3e. VNFeaturePrint image comparison (tiebreaker)             │
// │                                                                 │
// │  Step 4: Art Variant Resolution                                 │
// │    - Query all cards with same name+set                         │
// │    - If multiple art variants exist, compare art regions        │
// │    - Returns exact variant (#80a Spring vs #80d Winter)         │
// │                                                                 │
// └─────────────────────────────────────────────────────────────────┘

// MARK: - Protocol

/// The card identification pipeline takes raw image data and returns
/// the exact Card printing, including expansion, collector number,
/// and art variant.
protocol CardIdentificationPipelineProtocol: Sendable {
    /// Identifies a single card from raw image data.
    /// Returns nil if the card cannot be identified.
    func identify(imageData: Data) async -> Card?

    /// Identifies a single card from a CGImage (skips downsample, runs card detection + full pipeline).
    func identify(cgImage: CGImage) async -> Card?

    /// Identifies a card from a pre-cropped CGImage (skips downsample + card detection).
    /// When `visualOnly` is true, only visual matching is tried — OCR fallback is skipped.
    func identifyCropped(cardImage: CGImage, visualOnly: Bool) async -> Card?

    /// Identifies all cards visible in raw image data.
    /// Detects multiple card rectangles, identifies each independently.
    /// Falls back to single-card identification if multi-detect finds nothing.
    func identifyAll(imageData: Data) async -> [Card]

    /// Identifies a card using Gemini Vision API only (no local pipeline).
    /// Returns nil if Gemini is not configured or fails.
    func identifyWithGemini(cgImage: CGImage) async -> Card?

    /// Identifies all cards in a full image using Gemini Vision API.
    /// Returns analysis text and array of (card, boundingBox) pairs. Uses a single API call.
    func identifyAllWithGemini(image: CGImage) async -> (analysis: String?, cards: [(card: Card, bbox: CGRect?)])

    /// Saves a card image as a training sample for the embedding store.
    /// Used to feed Gemini-identified results back into local ML.
    func learnFromIdentification(cardImage: CGImage, card: Card) async

    /// Identifies cards across multiple photos in one Gemini call.
    /// Each photo may contain multiple cards. Each detection becomes one entry in
    /// `cards` (Gemini's `quantity` is expanded so 4× of the same card → 4 entries).
    /// `error` is non-nil when the API call failed end-to-end so callers can
    /// distinguish a real failure from "Gemini saw no cards".
    func identifyBatch(images: [CGImage]) async -> BatchIdentificationResult

    /// Clears the FeaturePrint cache (e.g., before batch identification of a new photo).
    func clearFeaturePrintCache() async
}

/// Result of a multi-photo batch identification pass.
/// `cards` lists one entry per detected card (quantities already expanded).
/// Each entry carries the bbox in the source photo when Gemini returned one.
/// `analysis` is an optional aggregate prose summary suitable for an "analysis" UI card.
/// `error` is non-nil only when the API call failed end-to-end; an empty `cards`
/// with `error == nil` means "Gemini ran but saw no recognizable cards".
struct BatchIdentificationResult {
    let cards: [BatchIdentifiedCard]
    let payloadBytes: Int
    let analysis: String?
    let error: String?
}

struct BatchIdentifiedCard: Equatable {
    let imageIndex: Int
    let card: Card
    /// Fractional coords (0–1) within the source photo at `imageIndex`. Nil when Gemini
    /// didn't report a bounding box for this detection.
    let boundingBox: BatchBoundingBox?
}

// MARK: - Implementation

// MARK: - Printing Scorer (Testable)

/// Input signals extracted from OCR passes, fed into the scoring function.
struct PrintingScorerInput {
    /// Bottom-bar OCR results (set code + collector number).
    var bottomBarResults: [(setCode: String, collectorNumber: String?, setTotal: Int?, confidence: Double)]
    /// Collector info from full-card OCR.
    var fullCollectorCandidates: [(collectorNumber: String, setCode: String?)]
    /// Artist name extracted from full-card OCR.
    var artistName: String?
    /// Copyright year extracted from full-card OCR.
    var copyrightYear: Int?
    /// Illustration ID from the visual match.
    var illustrationID: String?
    /// Scryfall ID of the printing that won the set-symbol visual comparison.
    /// Nil when symbol comparison was skipped or failed.
    var symbolMatchWinnerID: String?

    init(
        bottomBarResults: [(setCode: String, collectorNumber: String?, setTotal: Int?, confidence: Double)] = [],
        fullCollectorCandidates: [(collectorNumber: String, setCode: String?)] = [],
        artistName: String? = nil,
        copyrightYear: Int? = nil,
        illustrationID: String? = nil,
        symbolMatchWinnerID: String? = nil
    ) {
        self.bottomBarResults = bottomBarResults
        self.fullCollectorCandidates = fullCollectorCandidates
        self.artistName = artistName
        self.copyrightYear = copyrightYear
        self.illustrationID = illustrationID
        self.symbolMatchWinnerID = symbolMatchWinnerID
    }
}

/// Pure scoring logic for printing resolution, extracted for testability.
///
/// Given a list of candidate printings and OCR-extracted signals, assigns
/// scores to each printing and returns the winner. The logic mirrors what
/// `resolveExactPrinting` does, minus the image/OCR infrastructure.
enum PrintingScorer {

    /// Scores all printings and returns the winner.
    ///
    /// Scoring weights:
    /// - Bottom-bar set code match: +3 (scaled by confidence)
    /// - Bottom-bar set code + collector# match: +7 additional (total 10)
    /// - Cross-set collector# match: +2
    /// - Set total consistency: +1 / impossible: -5
    /// - Full-card collector info set code: +2, with collector# +3 additional
    /// - Artist match: +4, unique to one set: +2 bonus
    /// - Copyright year match: +1
    /// - Illustration ID match: +2
    /// - Symbol match winner: +1 (only when other signals > 0)
    /// - Tiebreak: oldest release date, then lowest collector number
    static func pickWinner(printings: [Card], input: PrintingScorerInput) -> Card? {
        guard !printings.isEmpty else { return nil }
        if printings.count == 1 { return printings[0] }

        var scores: [String: Double] = [:]
        for p in printings { scores[p.scryfallID] = 0 }

        // Signal 1: Bottom-bar set code + collector number
        for result in input.bottomBarResults {
            let lowerCode = result.setCode.lowercased()
            for p in printings where p.set.code == lowerCode {
                scores[p.scryfallID, default: 0] += 3.0 * result.confidence
                if let num = result.collectorNumber {
                    let stripped = String(Int(num) ?? 0)
                    let pStripped = String(Int(p.collectorNumber) ?? -1)
                    if p.collectorNumber == num || pStripped == stripped {
                        scores[p.scryfallID, default: 0] += 7.0
                    }
                }
            }
            if let num = result.collectorNumber {
                let stripped = String(Int(num) ?? 0)
                for p in printings {
                    let pStripped = String(Int(p.collectorNumber) ?? -1)
                    if p.collectorNumber == num || pStripped == stripped {
                        scores[p.scryfallID, default: 0] += 2.0
                    }
                }
            }
            if let setTotal = result.setTotal, setTotal > 0 {
                for p in printings {
                    let pNum = Int(p.collectorNumber.filter(\.isNumber)) ?? 0
                    if pNum > setTotal {
                        scores[p.scryfallID, default: 0] -= 5.0
                    } else if pNum > 0 {
                        scores[p.scryfallID, default: 0] += 1.0
                    }
                }
            }
        }

        // Signal 2: Full-card collector info
        for candidate in input.fullCollectorCandidates {
            if let setCode = candidate.setCode {
                let lowerCode = setCode.lowercased()
                for p in printings where p.set.code == lowerCode {
                    scores[p.scryfallID, default: 0] += 2.0
                    if !candidate.collectorNumber.isEmpty && p.collectorNumber == candidate.collectorNumber {
                        scores[p.scryfallID, default: 0] += 3.0
                    }
                }
            }
        }

        // Signal 3: Artist name
        if let artist = input.artistName {
            let ocrWords = Set(artist.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 4 })
            if !ocrWords.isEmpty {
                var matchedSets: [String] = []
                for p in printings {
                    guard let pArtist = p.artist else { continue }
                    let dbWords = Set(pArtist.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 4 })
                    if !ocrWords.intersection(dbWords).isEmpty {
                        scores[p.scryfallID, default: 0] += 4.0
                        matchedSets.append(p.set.code)
                    }
                }
                if Set(matchedSets).count == 1 {
                    let theSet = Set(matchedSets).first!
                    for p in printings where p.set.code == theSet {
                        scores[p.scryfallID, default: 0] += 2.0
                    }
                }
            }
        }

        // Signal 4: Copyright year
        if let year = input.copyrightYear {
            let validYears = Set([String(year - 1), String(year), String(year + 1)])
            for p in printings {
                if let rel = p.releasedAt, rel.count >= 4, validYears.contains(String(rel.prefix(4))) {
                    scores[p.scryfallID, default: 0] += 1.0
                }
            }
        }

        // Signal 5: Illustration ID from visual match
        if let illID = input.illustrationID, !illID.isEmpty {
            for p in printings where p.illustrationID == illID {
                scores[p.scryfallID, default: 0] += 2.0
            }
        }

        // Signal 6: Symbol match winner — only when other signals fired
        let maxScoreBeforeSymbol = scores.values.max() ?? 0
        if let winnerID = input.symbolMatchWinnerID, maxScoreBeforeSymbol > 0 {
            scores[winnerID, default: 0] += 1.0
        }

        // Pick winner: highest score, tiebreak by oldest release, then lowest collector#
        let sorted = printings.sorted { a, b in
            let sa = scores[a.scryfallID] ?? 0
            let sb = scores[b.scryfallID] ?? 0
            if sa != sb { return sa > sb }
            let da = a.releasedAt ?? "9999"
            let db = b.releasedAt ?? "9999"
            if da != db { return da < db }
            return (Int(a.collectorNumber.filter(\.isNumber)) ?? 9999) < (Int(b.collectorNumber.filter(\.isNumber)) ?? 9999)
        }

        return sorted.first
    }
}

/// The complete card identification engine.
///
/// This is the core of the app — all identification logic lives here.
/// The ViewModel should delegate to this pipeline and not contain
/// identification logic directly.
struct CardIdentificationPipeline: CardIdentificationPipelineProtocol {

    // MARK: - Dependencies

    /// Image preparation
    private let imageProcessor: ImageProcessor
    private let cardDetector: CardDetector

    /// OCR and signal extraction
    private let recognizer: TextRecognizerProtocol
    private let nameExtractor: CardNameExtractor
    private let collectorInfoExtractor: CollectorInfoExtractor
    private let artistExtractor: ArtistExtractor
    private let copyrightYearExtractor: CopyrightYearExtractor
    private let borderColorDetector: BorderColorDetector

    /// Printing resolution
    private let imageMatcher: ImageMatcher
    private let repository: CardRepositoryProtocol

    /// Art variant resolution
    private let artVariantMatcher: ArtVariantMatcher

    /// Visual search (primary identification — nil if index not available)
    private let visualSearchEngine: VisualSearchEngine?

    /// VNFeaturePrint cache (grows as user scans cards — nil if not configured)
    private let featurePrintCache: FeaturePrintCache?

    /// Persistent k-NN embedding store — learns from user corrections
    private let embeddingStore: VisualEmbeddingStore?

    // MARK: - Initialization

    init(
        recognizer: TextRecognizerProtocol,
        repository: CardRepositoryProtocol,
        visualSearchEngine: VisualSearchEngine? = nil,
        featurePrintCache: FeaturePrintCache? = nil,
        embeddingStore: VisualEmbeddingStore? = nil,
        imageProcessor: ImageProcessor = ImageProcessor(),
        cardDetector: CardDetector = CardDetector(),
        nameExtractor: CardNameExtractor = CardNameExtractor(),
        collectorInfoExtractor: CollectorInfoExtractor = CollectorInfoExtractor(),
        artistExtractor: ArtistExtractor = ArtistExtractor(),
        copyrightYearExtractor: CopyrightYearExtractor = CopyrightYearExtractor(),
        borderColorDetector: BorderColorDetector = BorderColorDetector(),
        imageMatcher: ImageMatcher = ImageMatcher(),
        artVariantMatcher: ArtVariantMatcher = ArtVariantMatcher()
    ) {
        self.recognizer = recognizer
        self.repository = repository
        self.visualSearchEngine = visualSearchEngine
        self.featurePrintCache = featurePrintCache
        self.embeddingStore = embeddingStore
        self.imageProcessor = imageProcessor
        self.cardDetector = cardDetector
        self.nameExtractor = nameExtractor
        self.collectorInfoExtractor = collectorInfoExtractor
        self.artistExtractor = artistExtractor
        self.copyrightYearExtractor = copyrightYearExtractor
        self.borderColorDetector = borderColorDetector
        self.imageMatcher = imageMatcher
        self.artVariantMatcher = artVariantMatcher
    }

    // MARK: - Public API

    /// Identifies a card from a pre-cropped CGImage (e.g., a grid cell from Deck Photo mode).
    /// Skips downsampling and card detection — the image IS the card.
    /// Does NOT cache results — deck photo cells are too low-resolution for reliable caching.
    /// Only single-card scans and explicit user corrections feed the cache.
    /// When `visualOnly` is true, the pipeline won't fall back to OCR
    /// if visual search fails — the blob is assumed to be a non-card
    /// (playmat logo, shadow, etc.). Used by the deck photo scan where
    /// color segmentation may produce blobs that aren't actual cards.
    func identifyCropped(cardImage: CGImage, visualOnly: Bool = false) async -> Card? {
        print("[MTGScanner] Identifying cropped image \(cardImage.width)x\(cardImage.height) visualOnly=\(visualOnly)")

        let finalImage = cardImage

        // Strategy 0: FP cache — used for NAME hint only, never for printing.
        // The cache may store a stale/wrong printing from a previous scan.
        // Printing is always resolved fresh via metadata + image comparison.
        // (Cache name is used inside resolveByVisualSearch for cross-validation.)

        // Strategy 1: Visual search
        if let match = await resolveByVisualSearch(cardImage: finalImage, wasCropped: false) {
            // Auto-learn: save this identification as a training sample
            if let store = embeddingStore {
                await store.addSample(
                    cardImage: finalImage,
                    cardName: match.name,
                    setCode: match.set.code,
                    collectorNumber: match.collectorNumber
                )
            }
            return match
        }

        // Strategy 2: OCR fallback
        if visualOnly { return nil }

        if let identified = await resolvePrinting(cardImage: finalImage, wasCropped: false) {
            let finalCard = await resolveArtVariant(card: identified, cardImage: finalImage)

            // Auto-learn: save this identification as a training sample
            if let store = embeddingStore {
                await store.addSample(
                    cardImage: finalImage,
                    cardName: finalCard.name,
                    setCode: finalCard.set.code,
                    collectorNumber: finalCard.collectorNumber
                )
            }

            return finalCard
        }

        // Strategy 3: Gemini Vision API fallback
        if GeminiVisionService.isConfigured {
            print("[MTGScanner] Local pipeline failed, trying Gemini Vision...")
            if let result = await GeminiVisionService.shared.identifyCard(image: finalImage) {
                // Look up the card name in local DB
                if let printings = try? await repository.findAllPrintings(name: result.cardName),
                   !printings.isEmpty {
                    // If Gemini provided set+collector, find exact printing
                    if let sc = result.setCode, let cn = result.collectorNumber {
                        if let exact = printings.first(where: { $0.set.code == sc && $0.collectorNumber == cn }) {
                            print("[MTGScanner] Gemini: exact printing match \(exact.name) [\(exact.set.code)]")
                            return exact
                        }
                    }
                    // Otherwise return the best printing
                    let match = await resolveExactPrinting(
                        cardImage: finalImage,
                        cardName: result.cardName,
                        printings: printings,
                        illustrationID: nil
                    )
                    if let match {
                        print("[MTGScanner] Gemini: resolved printing \(match.name) [\(match.set.code)]")
                        return match
                    }
                    // Last resort: return first printing
                    print("[MTGScanner] Gemini: using first printing for \(result.cardName)")
                    return printings.first
                }
            }
        }

        return nil
    }

    /// Identifies a card from raw image data.
    ///
    /// Runs the full pipeline: image preparation → OCR → printing resolution → art variant.
    /// Returns nil if the card cannot be identified at any step.
    func identify(imageData: Data) async -> Card? {
        // Step 0: Image preparation
        guard let rawImage = imageProcessor.downsample(data: imageData) else {
            return nil
        }

        let croppedCard = await cardDetector.detectAndCrop(from: rawImage)
        let cardImage = croppedCard ?? rawImage
        let wasCropped = croppedCard != nil

        print("[MTGScanner] Card detection: \(wasCropped ? "✓ cropped" : "✗ using raw image")")

        // OCR-based printing resolution (the original working flow)
        guard let identified = await resolvePrinting(cardImage: cardImage, wasCropped: wasCropped) else {
            return nil
        }

        let finalCard = await resolveArtVariant(card: identified, cardImage: cardImage)

        // Auto-learn: save this identification as a training sample
        if let store = embeddingStore {
            await store.addSample(
                cardImage: cardImage,
                cardName: finalCard.name,
                setCode: finalCard.set.code,
                collectorNumber: finalCard.collectorNumber
            )
        }

        // Cache the result for future FeaturePrint lookups
        if let cache = featurePrintCache,
           let artImage = artVariantMatcher.extractArtRegion(from: cardImage) {
            await cache.cache(
                illustrationID: finalCard.illustrationID ?? "",
                cardName: finalCard.name,
                setCode: finalCard.set.code,
                collectorNumber: finalCard.collectorNumber,
                artImage: artImage
            )
            await cache.save()
        }

        return finalCard
    }

    func identify(cgImage: CGImage) async -> Card? {
        let croppedCard = await cardDetector.detectAndCrop(from: cgImage)
        let cardImage = croppedCard ?? cgImage
        let wasCropped = croppedCard != nil

        print("[MTGScanner] Card detection: \(wasCropped ? "✓ cropped" : "✗ using raw image")")

        // OCR-based printing resolution (the original working flow)
        guard let identified = await resolvePrinting(cardImage: cardImage, wasCropped: wasCropped) else {
            return nil
        }

        let finalCard = await resolveArtVariant(card: identified, cardImage: cardImage)

        // Auto-learn: save this identification as a training sample
        if let store = embeddingStore {
            await store.addSample(
                cardImage: cardImage,
                cardName: finalCard.name,
                setCode: finalCard.set.code,
                collectorNumber: finalCard.collectorNumber
            )
        }

        if let cache = featurePrintCache,
           let artImage = artVariantMatcher.extractArtRegion(from: cardImage) {
            await cache.cache(
                illustrationID: finalCard.illustrationID ?? "",
                cardName: finalCard.name,
                setCode: finalCard.set.code,
                collectorNumber: finalCard.collectorNumber,
                artImage: artImage
            )
            await cache.save()
        }

        return finalCard
    }

    /// Identifies all cards visible in the image data.
    ///
    /// Detects multiple card rectangles, perspective-corrects each,
    /// and runs the full identification pipeline on each card independently.
    /// Falls back to single-card identification if multi-detect finds nothing.
    func identifyAll(imageData: Data) async -> [Card] {
        // Always use the proven single-card pipeline first
        // This handles 90%+ of photos correctly
        if let card = await identify(imageData: imageData) {
            return [card]
        }

        return []
    }

    func learnFromIdentification(cardImage: CGImage, card: Card) async {
        // Save to embedding store (persistent k-NN)
        if let store = embeddingStore {
            await store.addSample(
                cardImage: cardImage,
                cardName: card.name,
                setCode: card.set.code,
                collectorNumber: card.collectorNumber
            )
        }
        // Cache in FeaturePrint cache (volatile, session-level)
        if let cache = featurePrintCache,
           let artImage = artVariantMatcher.extractArtRegion(from: cardImage) {
            await cache.cache(
                illustrationID: card.illustrationID ?? "",
                cardName: card.name,
                setCode: card.set.code,
                collectorNumber: card.collectorNumber,
                artImage: artImage
            )
        }
    }

    func clearFeaturePrintCache() async {
        await featurePrintCache?.clear()
    }

    func identifyAllWithGemini(image: CGImage) async -> (analysis: String?, cards: [(card: Card, bbox: CGRect?)]) {
        guard GeminiVisionService.isConfigured else { return (nil, []) }
        guard let result = await GeminiVisionService.shared.identifyAllCards(image: image) else { return (nil, []) }
        let results = result.cards
        let analysis = result.analysis

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        print("[Gemini Pipeline] Processing \(results.count) card entries from Gemini:")
        for (i, r) in results.enumerated() {
            print("  [\(i)] \(r.quantity)x \(r.cardName) [\(r.setCode ?? "?")] bbox=\(r.boundingBox != nil)")
        }
        var cards: [(card: Card, bbox: CGRect?)] = []
        for result in results {
            var printings = (try? await repository.findAllPrintings(name: result.cardName)) ?? []

            // Fuzzy fallback: if exact name not found, try searching
            if printings.isEmpty {
                print("[Gemini Pipeline] Exact name not found: '\(result.cardName)', trying search...")
                if let searchResults = try? await repository.searchCards(query: result.cardName),
                   !searchResults.isEmpty {
                    // Filter to exact case-insensitive matches if possible
                    let exact = searchResults.filter { $0.name.lowercased() == result.cardName.lowercased() }
                    printings = exact.isEmpty ? searchResults : exact
                    print("[Gemini Pipeline] Search found \(printings.count) results")
                } else {
                    print("[Gemini Pipeline] SKIPPED: '\(result.cardName)' not in DB")
                }
            }

            if !printings.isEmpty {
                var card: Card?
                if let sc = result.setCode, let cn = result.collectorNumber {
                    // Exact set + collector match
                    card = printings.first(where: { $0.set.code == sc && $0.collectorNumber == cn })
                }
                if card == nil, let sc = result.setCode {
                    // Trust Gemini's set code — pick any printing from that set
                    card = printings.first(where: { $0.set.code == sc })
                }
                if card == nil { card = printings.first }

                if let card {
                    let bbox: CGRect? = result.boundingBox.map { b in
                        CGRect(x: b.x * imgW, y: b.y * imgH, width: b.w * imgW, height: b.h * imgH)
                    }
                    // Expand quantity: add N copies of the same card
                    for _ in 0..<max(1, result.quantity) {
                        cards.append((card: card, bbox: bbox))
                    }

                    // Auto-learn: crop + save to embedding store (once per unique card)
                    if let bbox,
                       let cropped = image.cropping(to: bbox.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))),
                       cropped.width > 50 && cropped.height > 50 {
                        await learnFromIdentification(cardImage: cropped, card: card)
                    }
                }
            }
        }
        return (analysis: analysis, cards: cards)
    }

    func identifyWithGemini(cgImage: CGImage) async -> Card? {
        guard GeminiVisionService.isConfigured else { return nil }
        guard let result = await GeminiVisionService.shared.identifyCard(image: cgImage) else { return nil }

        // Look up in local DB
        guard let printings = try? await repository.findAllPrintings(name: result.cardName),
              !printings.isEmpty else {
            print("[MTGScanner] Gemini identified '\(result.cardName)' but not found in DB")
            return nil
        }

        var card: Card?

        // Try exact printing match first
        if let sc = result.setCode, let cn = result.collectorNumber {
            card = printings.first(where: { $0.set.code == sc && $0.collectorNumber == cn })
        }

        // Resolve best printing using multi-signal scoring
        if card == nil {
            card = await resolveExactPrinting(
                cardImage: cgImage, cardName: result.cardName,
                printings: printings, illustrationID: nil
            )
        }

        if card == nil { card = printings.first }

        // Auto-learn from Gemini result
        if let card {
            await learnFromIdentification(cardImage: cgImage, card: card)
        }

        return card
    }

    // MARK: - Batch Identification

    /// Identifies cards across multiple photos in one Gemini call.
    /// See `BatchIdentificationResult` for the contract. Each Gemini detection's
    /// `quantity` is expanded into individual entries — a single photo containing
    /// 4× of the same card produces 4 entries, all sharing the same `imageIndex`.
    func identifyBatch(images: [CGImage]) async -> BatchIdentificationResult {
        guard GeminiVisionService.isConfigured else {
            return BatchIdentificationResult(cards: [], payloadBytes: 0, analysis: nil, error: "Gemini is not configured. Add an API key in Settings.")
        }
        let response = await GeminiVisionService.shared.identifyCardBatch(images: images)
        if let error = response.error {
            return BatchIdentificationResult(cards: [], payloadBytes: response.payloadBytes, analysis: response.analysis, error: error)
        }

        var resolved: [BatchIdentifiedCard] = []
        for batchResult in response.cards {
            var printings = (try? await repository.findAllPrintings(name: batchResult.cardName)) ?? []

            if printings.isEmpty {
                if let searchResults = try? await repository.searchCards(query: batchResult.cardName),
                   !searchResults.isEmpty {
                    let exact = searchResults.filter { $0.name.lowercased() == batchResult.cardName.lowercased() }
                    printings = exact.isEmpty ? searchResults : exact
                }
            }

            guard !printings.isEmpty else { continue }

            var card: Card?
            if let sc = batchResult.setCode, let cn = batchResult.collectorNumber {
                card = printings.first(where: { $0.set.code == sc && $0.collectorNumber == cn })
            }
            if card == nil, let sc = batchResult.setCode {
                card = printings.first(where: { $0.set.code == sc })
            }
            if card == nil { card = printings.first }

            if let card {
                for _ in 0..<max(1, batchResult.quantity) {
                    resolved.append(BatchIdentifiedCard(
                        imageIndex: batchResult.imageIndex,
                        card: card,
                        boundingBox: batchResult.boundingBox
                    ))
                }
            }
        }
        return BatchIdentificationResult(cards: resolved, payloadBytes: response.payloadBytes, analysis: response.analysis, error: nil)
    }

    // MARK: - Step 2: OCR Signal Extraction

    /// Extracts all available signals from the card image via OCR.
    private struct OCRSignals {
        let scanResults: [ScanResult]
        let cardName: String
        let collectorCandidates: [CollectorInfo]
        let artistName: String?
        let copyrightYear: Int?
        let hasOldTypeLine: Bool
        let detectedBorder: BorderColor?
    }

    private func extractOCRSignals(from cardImage: CGImage, wasCropped: Bool) async -> OCRSignals? {
        print("[MTGScanner] Running OCR on image \(cardImage.width)x\(cardImage.height)")
        do {
            let scanResults = try await recognizer.recognizeText(in: cardImage)

            for result in scanResults {
                print("[MTGScanner] OCR: '\(result.recognizedText)' conf=\(String(format: "%.2f", result.confidence)) y=\(String(format: "%.3f", result.boundingBox.origin.y))")
            }

            guard let cardName = nameExtractor.extractCardName(from: scanResults) else {
                return nil
            }

            let collectorCandidates = collectorInfoExtractor.extractAllCandidates(from: scanResults)
            let artistName = artistExtractor.extractArtist(from: scanResults)
            let copyrightYear = copyrightYearExtractor.extractCopyrightEndYear(from: scanResults)
            let hasOldTypeLine = scanResults.contains { $0.recognizedText.lowercased().hasPrefix("summon") }
            let detectedBorder = wasCropped ? borderColorDetector.detectBorderColor(in: cardImage) : nil

            print("[MTGScanner] Name: '\(cardName)' | Collector: \(collectorCandidates) | Artist: \(artistName ?? "nil") | Year: \(copyrightYear.map(String.init) ?? "nil") | Border: \(detectedBorder?.rawValue ?? "nil") | OldFrame: \(hasOldTypeLine)")

            return OCRSignals(
                scanResults: scanResults,
                cardName: cardName,
                collectorCandidates: collectorCandidates,
                artistName: artistName,
                copyrightYear: copyrightYear,
                hasOldTypeLine: hasOldTypeLine,
                detectedBorder: detectedBorder
            )
        } catch {
            print("[MTGScanner] OCR failed: \(error)")
            return nil
        }
    }

    /// Upscales a CGImage to the given dimensions using high-quality interpolation.
    /// Verifies an identification using the local pHash visual index.
    /// Computes pHash of the crop's art region and compares against the
    /// identified card's illustration — no download needed.
    /// If the art doesn't match, the identification is wrong (e.g., cache
    /// Detects if the card contains CJK (Chinese/Japanese/Korean) text.
    /// Runs a fast OCR pass with CJK languages enabled — necessary because
    /// English-only OCR interprets CJK characters as garbled Latin text.
    private func detectCJKText(in image: CGImage) async -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return false }

        for obs in (request.results ?? []) {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            let hasCJK = text.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) ||  // CJK Unified Ideographs
                (0x3400...0x4DBF).contains(scalar.value) ||  // CJK Extension A
                (0x3040...0x309F).contains(scalar.value) ||  // Hiragana
                (0x30A0...0x30FF).contains(scalar.value) ||  // Katakana
                (0xAC00...0xD7AF).contains(scalar.value)     // Hangul
            }
            if hasCJK { return true }
        }
        return false
    }

    private func upscaleImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// Converts image to high-contrast grayscale for better OCR on small/glary text.
    /// Applies: grayscale → contrast stretch → sharpen via Core Image.
    private func enhanceForOCR(_ image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let context = CIContext()

        // Convert to grayscale and boost contrast
        guard let colorControls = CIFilter(name: "CIColorControls") else { return nil }
        colorControls.setValue(ciImage, forKey: kCIInputImageKey)
        colorControls.setValue(0.0, forKey: kCIInputSaturationKey)  // Grayscale
        colorControls.setValue(1.5, forKey: kCIInputContrastKey)    // Boost contrast
        colorControls.setValue(0.1, forKey: kCIInputBrightnessKey)  // Slight brighten

        guard let grayImage = colorControls.outputImage else { return nil }

        // Sharpen
        guard let sharpen = CIFilter(name: "CISharpenLuminance") else {
            return context.createCGImage(grayImage, from: grayImage.extent)
        }
        sharpen.setValue(grayImage, forKey: kCIInputImageKey)
        sharpen.setValue(1.0, forKey: kCIInputSharpnessKey)

        guard let output = sharpen.outputImage else {
            return context.createCGImage(grayImage, from: grayImage.extent)
        }
        return context.createCGImage(output, from: output.extent)
    }

    // MARK: - Exact Printing Resolution

    /// Parsed info from the bottom bar: set code, optional collector number, set total, confidence.
    private struct BottomBarResult: CustomStringConvertible {
        let setCode: String
        let collectorNumber: String?
        let setTotal: Int?  // e.g., 38 from "014/038"
        let confidence: Double
        var description: String { "\(setCode)(\(collectorNumber ?? "?")/\(setTotal.map(String.init) ?? "?") conf:\(confidence))" }
    }

    /// Single, clean method to resolve the exact printing of a card.
    /// Runs exactly 2 OCR passes and scores all candidate printings.
    ///
    /// Pass 1: Full-card OCR -> extracts artist, copyright year, collector info
    /// Pass 2: Focused bottom-bar OCR (crop + upscale + enhance) -> set code + collector#
    ///
    /// Each printing gets scored based on all available signals:
    /// - Set code + collector# exact match: +10 (definitive)
    /// - Set code match: +3
    /// - Collector# match (cross-set): +2
    /// - Artist match: +4 (unique to one set: +2 bonus)
    /// - Copyright year match: +1
    /// - Illustration ID match: +2
    /// - Set total consistency: +1 / impossible: -5
    /// Tiebreak: oldest release date (original printing)
    private func resolveExactPrinting(
        cardImage: CGImage,
        cardName: String,
        printings: [Card],
        illustrationID: String?
    ) async -> Card? {
        guard !printings.isEmpty else { return nil }
        if printings.count == 1 { return printings[0] }

        var scores: [String: Double] = [:]
        for p in printings { scores[p.scryfallID] = 0 }

        // === PASS 1: Full-card OCR ===
        let fullOCRResults = try? await recognizer.recognizeText(in: cardImage)

        // Extract artist name
        let artistName: String?
        if let results = fullOCRResults {
            artistName = artistExtractor.extractArtist(from: results)
        } else {
            artistName = nil
        }

        // Extract copyright year
        let copyrightYear: Int?
        if let results = fullOCRResults {
            copyrightYear = copyrightYearExtractor.extractCopyrightEndYear(from: results)
        } else {
            copyrightYear = nil
        }

        // Extract collector info from full card
        let fullCollectorCandidates: [CollectorInfo]
        if let results = fullOCRResults {
            fullCollectorCandidates = collectorInfoExtractor.extractAllCandidates(from: results)
        } else {
            fullCollectorCandidates = []
        }

        // === PASS 2: Focused bottom-bar OCR (crop + upscale + enhance) ===
        let knownSetCodes = Set(printings.map { $0.set.code.uppercased() })
        let bottomBarResults = await runBottomBarOCR(cardImage: cardImage, knownSetCodes: knownSetCodes)

        // === SCORING ===

        // Signal 1: Bottom-bar set code + collector number
        for result in bottomBarResults {
            let lowerCode = result.setCode.lowercased()
            for p in printings where p.set.code == lowerCode {
                scores[p.scryfallID, default: 0] += 3.0 * result.confidence
                // Set code + collector# exact match is definitive
                if let num = result.collectorNumber {
                    let stripped = String(Int(num) ?? 0)
                    let pStripped = String(Int(p.collectorNumber) ?? -1)
                    if p.collectorNumber == num || pStripped == stripped {
                        scores[p.scryfallID, default: 0] += 7.0  // 3 + 7 = 10 total
                    }
                }
            }
            // Cross-set collector# match
            if let num = result.collectorNumber {
                let stripped = String(Int(num) ?? 0)
                for p in printings {
                    let pStripped = String(Int(p.collectorNumber) ?? -1)
                    if p.collectorNumber == num || pStripped == stripped {
                        scores[p.scryfallID, default: 0] += 2.0
                    }
                }
            }
            // Set total filter: "014/038" means set has 38 cards
            if let setTotal = result.setTotal, setTotal > 0 {
                for p in printings {
                    let pNum = Int(p.collectorNumber.filter(\.isNumber)) ?? 0
                    if pNum > setTotal {
                        scores[p.scryfallID, default: 0] -= 5.0
                    } else if pNum > 0 {
                        scores[p.scryfallID, default: 0] += 1.0
                    }
                }
            }
        }

        // Signal 2: Full-card collector info (set code + number from full OCR)
        for candidate in fullCollectorCandidates {
            if let setCode = candidate.setCode {
                let lowerCode = setCode.lowercased()
                for p in printings where p.set.code == lowerCode {
                    scores[p.scryfallID, default: 0] += 2.0
                    if !candidate.collectorNumber.isEmpty && p.collectorNumber == candidate.collectorNumber {
                        scores[p.scryfallID, default: 0] += 3.0
                    }
                }
            }
        }

        // Signal 3: Artist name
        if let artist = artistName {
            let ocrWords = Set(artist.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 4 })
            if !ocrWords.isEmpty {
                var matchedSets: [String] = []
                for p in printings {
                    guard let pArtist = p.artist else { continue }
                    let dbWords = Set(pArtist.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 4 })
                    if !ocrWords.intersection(dbWords).isEmpty {
                        scores[p.scryfallID, default: 0] += 4.0
                        matchedSets.append(p.set.code)
                    }
                }
                // Unique artist bonus
                if Set(matchedSets).count == 1 {
                    let theSet = Set(matchedSets).first!
                    for p in printings where p.set.code == theSet {
                        scores[p.scryfallID, default: 0] += 2.0
                    }
                }
            }
        }

        // Signal 4: Copyright year
        if let year = copyrightYear {
            let validYears = Set([String(year - 1), String(year), String(year + 1)])
            for p in printings {
                if let rel = p.releasedAt, rel.count >= 4, validYears.contains(String(rel.prefix(4))) {
                    scores[p.scryfallID, default: 0] += 1.0
                }
            }
        }

        // Signal 5: Illustration ID from visual match
        if let illID = illustrationID, !illID.isEmpty {
            for p in printings where p.illustrationID == illID {
                scores[p.scryfallID, default: 0] += 2.0
            }
        }

        // Signal 6: Set symbol visual comparison
        // Download reference images for top candidates and compare the set symbol
        // region visually. Each set has a unique symbol — even at small sizes,
        // shape differences are significant (sword vs tree vs skull).
        //
        // IMPORTANT: Only apply when at least one other signal fired. When all
        // scores are 0 (e.g., deck photo with unreadable bottom bar), the symbol
        // comparison is unreliable at small crop sizes (~30-50px) and can boost
        // the wrong printing (e.g., Secret Lair Drop instead of M14). In that
        // case, let the oldest-release tiebreak decide instead.
        let currentScores = scores
        let maxScoreBeforeSymbol = currentScores.values.max() ?? 0
        let topCandidates = printings
            .sorted { (currentScores[$0.scryfallID] ?? 0) > (currentScores[$1.scryfallID] ?? 0) }
            .prefix(5)

        if topCandidates.count > 1, maxScoreBeforeSymbol > 0 {
            let symbolMatcher = SetSymbolMatcher()
            var candidateImages: [(index: Int, image: CGImage)] = []

            for (i, candidate) in topCandidates.enumerated() {
                guard let urlString = candidate.imageURIs["normal"] ?? candidate.imageURIs["small"],
                      let refImage = await imageMatcher.downloadImage(from: urlString) else { continue }
                candidateImages.append((index: i, image: refImage))
            }

            if !candidateImages.isEmpty {
                // Get OCR results for symbol extraction from user's photo
                let symbolScanResults = (try? await recognizer.recognizeText(in: cardImage)) ?? []

                let symDists = await symbolMatcher.symbolDistances(
                    sourceImage: cardImage,
                    candidateImages: candidateImages,
                    scanResults: symbolScanResults
                )

                // Find the best (lowest distance) symbol match
                var bestSymbolIdx: Int?
                var bestSymbolDist: Float = .greatestFiniteMagnitude
                for (i, dist) in symDists.enumerated() {
                    guard let d = dist else { continue }
                    if d < bestSymbolDist {
                        bestSymbolDist = d
                        bestSymbolIdx = i
                    }
                }

                if let bestIdx = bestSymbolIdx {
                    let topArray = Array(topCandidates)
                    let bestCandidate = topArray[candidateImages[bestIdx].index]
                    // Symbol matching is a tiebreaker (+1), not a primary signal.
                    // At small crop sizes (~30-50px), VNFeaturePrint is noisy and
                    // can incorrectly match wrong symbols (e.g., Secret Lair Drop
                    // matching instead of Tempest). Keep weight low to avoid
                    // overriding correct signals from OCR/artist/year.
                    scores[bestCandidate.scryfallID, default: 0] += 1.0
                    print("[MTGScanner] Symbol match: best=\(bestCandidate.set.code) (dist: \(bestSymbolDist))")
                }
            }
        } else if topCandidates.count > 1, maxScoreBeforeSymbol == 0 {
            print("[MTGScanner] Skipping symbol comparison — no OCR signals fired, relying on oldest-release tiebreak")
        }

        // === DIAGNOSTIC LOGGING ===
        // Log OCR signals extracted for this card
        print("[MTGScanner] resolveExactPrinting signals: artist=\(artistName ?? "nil") | copyrightYear=\(copyrightYear.map(String.init) ?? "nil") | illustrationID=\(illustrationID ?? "nil") | bottomBar=\(bottomBarResults.map { "\($0.setCode)#\($0.collectorNumber ?? "?")" }) | fullCollector=\(fullCollectorCandidates.map { "\($0.setCode ?? "?")#\($0.collectorNumber)" })")

        // === PICK WINNER ===
        let sorted = printings.sorted { a, b in
            let sa = scores[a.scryfallID] ?? 0
            let sb = scores[b.scryfallID] ?? 0
            if sa != sb { return sa > sb }
            // Tiebreak: newest release first — users are more likely to
            // own recent printings than Alpha/Beta originals. "Oldest first"
            // was actively wrong (see matchByMetadata comment).
            let da = a.releasedAt ?? "0000"
            let db = b.releasedAt ?? "0000"
            if da != db { return da > db }
            return (Int(a.collectorNumber.filter(\.isNumber)) ?? 9999) < (Int(b.collectorNumber.filter(\.isNumber)) ?? 9999)
        }

        if let best = sorted.first {
            let bestScore = scores[best.scryfallID] ?? 0
            print("[MTGScanner] resolveExactPrinting: winner=\(best.set.code) #\(best.collectorNumber) (\(best.set.name)) score=\(bestScore)")
            // Log top 5 with score breakdown for debugging
            for (i, p) in sorted.prefix(5).enumerated() {
                let s = scores[p.scryfallID] ?? 0
                print("[MTGScanner]   #\(i+1) \(p.set.code) #\(p.collectorNumber) (\(p.set.name)) released=\(p.releasedAt ?? "nil") artist=\(p.artist ?? "nil") illID=\(p.illustrationID ?? "nil") score=\(s)")
            }
            return best
        }
        return printings.first
    }

    /// Runs focused OCR on the bottom 15% of the card (cropped + upscaled + enhanced).
    /// Returns parsed set codes with collector numbers and set totals.
    private func runBottomBarOCR(cardImage: CGImage, knownSetCodes: Set<String>) async -> [BottomBarResult] {
        let stripHeight = max(Int(Double(cardImage.height) * 0.15), 1)
        let stripY = cardImage.height - stripHeight
        let cropRect = CGRect(x: 0, y: stripY, width: cardImage.width, height: stripHeight)
        guard let strip = cardImage.cropping(to: cropRect) else { return [] }

        // Upscale + enhance
        let targetHeight = max(strip.height, 200)
        let scale = CGFloat(targetHeight) / CGFloat(strip.height)
        let targetWidth = Int(CGFloat(strip.width) * scale)
        let ocrImage: CGImage
        if let upscaled = upscaleImage(strip, width: targetWidth, height: targetHeight),
           let enhanced = enhanceForOCR(upscaled) {
            ocrImage = enhanced
        } else if let upscaled = upscaleImage(strip, width: targetWidth, height: targetHeight) {
            ocrImage = upscaled
        } else {
            ocrImage = strip
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.0
        request.customWords = Array(knownSetCodes) + [
            // Standard expansions
            "CLB", "MID", "VOW", "NEO", "SNC", "DMU", "BRO", "ONE",
            "MOM", "WOE", "LCI", "MKM", "OTJ", "BLB", "DSK", "FDN",
            "AFR", "STX", "KHM", "ZNR", "IKO", "THB", "ELD", "WAR",
            "RNA", "GRN", "DOM", "RIX", "XLN", "AKH", "AER", "KLD",
            "EMN", "SOI", "OGW", "BFZ", "ORI", "DTK", "FRF", "KTK",
            // Masters / reprint / special
            "2X2", "2XM", "TSR", "MH1", "MH2", "MH3", "UMA", "IMA",
            "A25", "MM3", "MM2", "MMA", "40K", "WHO", "PIP", "ACR",
            // Core sets
            "M21", "M20", "M19", "M15", "M14", "M13", "M12", "M11", "M10",
            // Commander products
            "NEC", "NCC", "MIC", "AFC", "CMR", "MOC", "MKC", "VOC",
            "C21", "C20", "C19", "C18", "C17", "C16", "OTC", "BLC",
            "40K",  // Warhammer 40K (digit-first code)
            // Older sets
            "ICE", "ALL", "CSP", "5ED", "4ED", "3ED", "USG", "TMP",
            "MMQ", "INV", "ODY", "ONS", "MRD", "CHK", "RAV", "TSP",
            "LRW", "SHM", "ALA", "ZEN", "SOM", "ISD", "RTR", "THS",
            // Rarity + language
            "C", "U", "R", "M", "EN", "JP", "DE", "FR"
        ]

        let handler = VNImageRequestHandler(cgImage: ocrImage, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        guard let results = request.results, !results.isEmpty else { return [] }

        let combinedText = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        print("[MTGScanner] Bottom-bar OCR: '\(combinedText)'")

        var foundResults: [BottomBarResult] = []

        // Structured: "014/038 R NEC"
        let p1 = #"(\d{1,4})\s*[/:\-\.]\s*(\d{1,4})\s+[CURM]\s+([A-Z0-9]{2,5})"#
        if let regex = try? NSRegularExpression(pattern: p1, options: .caseInsensitive) {
            let nsText = combinedText as NSString
            for m in regex.matches(in: combinedText, range: NSRange(location: 0, length: nsText.length)) where m.numberOfRanges > 3 {
                let num = nsText.substring(with: m.range(at: 1))
                let total = nsText.substring(with: m.range(at: 2))
                let code = nsText.substring(with: m.range(at: 3)).uppercased()
                if code.count >= 2, code.count <= 5, code.contains(where: \.isLetter) {
                    foundResults.append(BottomBarResult(setCode: code, collectorNumber: num, setTotal: Int(total), confidence: 1.0))
                }
            }
        }
        // Standalone: "014 R NEC"
        let p2 = #"(\d{1,4})\s+[CURM]\s+([A-Z0-9]{2,5})"#
        if let regex = try? NSRegularExpression(pattern: p2, options: .caseInsensitive) {
            let nsText = combinedText as NSString
            for m in regex.matches(in: combinedText, range: NSRange(location: 0, length: nsText.length)) where m.numberOfRanges > 2 {
                let num = nsText.substring(with: m.range(at: 1))
                let code = nsText.substring(with: m.range(at: 2)).uppercased()
                if code.count >= 2, code.count <= 5, code.contains(where: \.isLetter),
                   !foundResults.contains(where: { $0.setCode == code }) {
                    foundResults.append(BottomBarResult(setCode: code, collectorNumber: num, setTotal: nil, confidence: 1.0))
                }
            }
        }
        // Token match
        let tokens = combinedText.uppercased()
            .replacingOccurrences(of: "\u{2022}", with: " ").replacingOccurrences(of: "\u{00B7}", with: " ")
            .replacingOccurrences(of: "\u{00A9}", with: " ").replacingOccurrences(of: "\u{2122}", with: " ")
            .split(separator: " ").map(String.init)
        for token in tokens where token.count >= 2 && token.count <= 5 && token.contains(where: \.isLetter) {
            if !foundResults.contains(where: { $0.setCode == token }) {
                foundResults.append(BottomBarResult(setCode: token, collectorNumber: nil, setTotal: nil, confidence: 0.5))
            }
        }

        return foundResults
    }

    // MARK: - Step 3: Printing Resolution

    private func resolvePrinting(cardImage: CGImage, wasCropped: Bool) async -> Card? {
        // Full OCR to get card name
        guard let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped) else {
            return nil
        }

        // Collector number + metadata matching
        if let match = await matchByCollectorNumber(signals: signals) {
            return match
        }
        if let match = await matchByMetadata(signals: signals, cardImage: cardImage) {
            return match
        }
        if let match = await matchByFirstCharCorrection(signals: signals, cardImage: cardImage) {
            return match
        }
        return await matchByAlternativeNames(signals: signals, cardImage: cardImage)
    }

    // MARK: - Step 1: Visual Search

    /// Uses VNFeaturePrint cache (and legacy pHash) to identify the card by its art region.
    /// If a match is found, uses OCR signals to narrow to the exact printing.
    /// Returns nil if visual search is unavailable or finds no match.
    private func resolveByVisualSearch(cardImage: CGImage, wasCropped: Bool) async -> Card? {
        guard let artImage = artVariantMatcher.extractArtRegion(from: cardImage) else {
            print("[MTGScanner] Visual search: could not extract art region")
            return nil
        }

        // Embedding store (persistent k-NN from corrections) — highest priority.
        // Trained from explicit user corrections, so it's the most reliable source.
        if let store = embeddingStore,
           let embeddingMatch = await store.findMatch(for: cardImage) {
            print("[MTGScanner] Embedding store match: '\(embeddingMatch.cardName)' (distance: \(String(format: "%.2f", embeddingMatch.distance)))")
            if let printings = try? await repository.findAllPrintings(name: embeddingMatch.cardName),
               !printings.isEmpty {
                if let match = await resolveExactPrinting(
                    cardImage: cardImage,
                    cardName: embeddingMatch.cardName,
                    printings: printings,
                    illustrationID: nil
                ) {
                    return match
                }
            }
        }

        // FeaturePrint cache — used for NAME cross-validation only.
        // NEVER trust the cache for printing (set/collector). Printing is
        // always resolved fresh via metadata + frame-masked image comparison.
        // Detect CJK early — used by both cache and pHash paths
        let isCJKCard = await detectCJKText(in: cardImage)

        var cacheHintName: String?
        if let cache = featurePrintCache,
           let cacheHit = await cache.search(artImage: artImage) {
            print("[MTGScanner] FeaturePrint cache candidate: '\(cacheHit.cardName)'")

            if isCJKCard {
                // Foreign-language card — trust cache name (art is the same)
                cacheHintName = cacheHit.cardName
                print("[MTGScanner] CJK card detected, trusting cache name: '\(cacheHintName!)'")
            } else if let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped) {
                let ocrWords = signals.cardName.lowercased().split(separator: " ").filter { $0.count >= 4 }
                let cacheWords = cacheHit.cardName.lowercased().split(separator: " ").filter { $0.count >= 4 }
                let allCacheWordsFound = cacheWords.allSatisfy { cw in
                    ocrWords.contains { ow in
                        if ow == cw { return true }
                        let maxDist = ow.count >= 8 ? 2 : 1
                        return levenshteinDistance(String(ow), String(cw)) <= maxDist
                    }
                }
                if !allCacheWordsFound && !ocrWords.isEmpty && !cacheWords.isEmpty {
                    // OCR disagrees with cache. Check if OCR name is a real card —
                    // if it is, OCR is probably right and cache is stale.
                    // If OCR name is NOT a real card, it's likely garbled foreign
                    // text → trust the cache (matched by art, more reliable).
                    let ocrNameExists = (try? await repository.findAllPrintings(name: signals.cardName))?.isEmpty == false
                    if ocrNameExists {
                        print("[MTGScanner] FeaturePrint cache rejected: OCR '\(signals.cardName)' is a real card ≠ cache '\(cacheHit.cardName)'")
                        // Don't trust cache — OCR found a valid different card name
                    } else {
                        // OCR name is garbage (foreign card or garbled text) — trust cache
                        cacheHintName = cacheHit.cardName
                        print("[MTGScanner] FeaturePrint cache: OCR '\(signals.cardName)' not in DB — trusting cache '\(cacheHit.cardName)' (likely foreign card)")
                    }
                } else {
                    let namesMatch = cacheHit.cardName.lowercased() == signals.cardName.lowercased()
                        || levenshteinDistance(cacheHit.cardName.lowercased(), signals.cardName.lowercased()) <= 2
                    cacheHintName = namesMatch ? cacheHit.cardName : signals.cardName
                    print("[MTGScanner] FeaturePrint cache confirmed name: '\(cacheHintName!)' — resolving printing fresh")
                }
            } else {
                // OCR failed — still use cache name as hint, but NOT printing
                cacheHintName = cacheHit.cardName
                print("[MTGScanner] FeaturePrint cache name hint (no OCR): '\(cacheHintName!)'")
            }
        }

        // If we have a card name (from cache or will get from pHash), use
        if let hintName = cacheHintName,
           let printings = try? await repository.findAllPrintings(name: hintName),
           !printings.isEmpty {
            if let match = await resolveExactPrinting(
                cardImage: cardImage,
                cardName: hintName,
                printings: printings,
                illustrationID: nil
            ) {
                return match
            }
        }

        // Fall back to legacy pHash visual search engine
        guard let visualEngine = visualSearchEngine else { return nil }

        // Foreign-language (CJK) cards need a relaxed pHash threshold because
        // the art crop may differ slightly from the English reference.
        let pHashThreshold = isCJKCard ? 14 : 8

        guard let match = visualEngine.bestMatch(for: artImage, maxDistance: pHashThreshold) else {
            print("[MTGScanner] Visual search: no match within threshold \(pHashThreshold)\(isCJKCard ? " (foreign card)" : "")")
            return nil
        }

        let distance = PerceptualHash.hammingDistance(
            PerceptualHash.compute(from: artImage) ?? 0,
            match.hash
        )
        print("[MTGScanner] \u{2713} Visual match: '\(match.cardName)' (distance: \(distance))")

        // Run OCR to get signals for cross-validation and printing refinement
        let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped)

        // Cross-validate: if OCR found a card name, check it's compatible with visual match.
        // Exception: foreign-language cards (CJK text) — trust the visual match since
        // art and illustration_id are identical across all languages.
        if isCJKCard {
            print("[MTGScanner] Foreign-language card detected, trusting visual match '\(match.cardName)'")
        } else if let signals {
            let ocrName = signals.cardName.lowercased()
            let visualName = match.cardName.lowercased()
            let ocrWords = ocrName.split(separator: " ").filter { $0.count >= 4 }
            let visualWords = visualName.split(separator: " ").filter { $0.count >= 4 }
            let hasCommonWord = ocrWords.contains { ow in
                visualWords.contains { vw in
                    ow == vw || (ow.count == vw.count && levenshteinClose(String(ow), String(vw)))
                }
            }
            if !hasCommonWord && !ocrWords.isEmpty {
                print("[MTGScanner] Visual match rejected: OCR '\(signals.cardName)' ≠ visual '\(match.cardName)'")
                return nil
            }
        } else if distance > 4 {
            // OCR couldn't read the card at all (glare, angle, sleeve).
            // Without OCR validation, require a very strict pHash match
            // to avoid false positives (e.g., Steam Vents → Game Trail).
            print("[MTGScanner] Visual match rejected: no OCR to validate, distance \(distance) > 4 (strict mode)")
            return nil
        }

        // Look up all printings for the matched card name
        guard let printings = try? await repository.findAllPrintings(name: match.cardName),
              !printings.isEmpty else {
            print("[MTGScanner] Visual match name '\(match.cardName)' not found in DB")
            return nil
        }

        // Resolve exact printing using multi-signal scoring
        return await resolveExactPrinting(
            cardImage: cardImage,
            cardName: match.cardName,
            printings: printings,
            illustrationID: match.illustrationID
        )
    }

    /// Tries common first-character OCR substitutions on the card name.
    /// Old-frame stylized fonts cause 'b'→'H', 'l'→'L' etc. errors.
    private func matchByFirstCharCorrection(signals: OCRSignals, cardImage: CGImage) async -> Card? {
        let name = signals.cardName
        guard !name.isEmpty else { return nil }

        let firstChar = name.first!
        // Common OCR substitutions for stylized first characters
        let replacements: [Character: [Character]] = [
            "b": ["H", "B", "h"],
            "l": ["L", "I", "l"],
            "f": ["F", "f"],
            "t": ["T", "t"],
            "r": ["R", "r"],
            "n": ["N", "n"],
            "m": ["M", "m"],
            "c": ["C", "c"],
            "d": ["D", "d"],
            "p": ["P", "p"],
        ]

        guard let candidates = replacements[firstChar] else { return nil }

        for replacement in candidates {
            var corrected = name
            corrected.replaceSubrange(corrected.startIndex...corrected.startIndex, with: String(replacement))

            if let printings = try? await repository.findAllPrintings(name: corrected),
               !printings.isEmpty {
                print("[MTGScanner] First-char correction: '\(name)' → '\(corrected)' (\(printings.count) printings)")

                let correctedSignals = OCRSignals(
                    scanResults: signals.scanResults,
                    cardName: corrected,
                    collectorCandidates: signals.collectorCandidates,
                    artistName: signals.artistName,
                    copyrightYear: signals.copyrightYear,
                    hasOldTypeLine: signals.hasOldTypeLine,
                    detectedBorder: signals.detectedBorder
                )
                return await matchByMetadata(signals: correctedSignals, cardImage: cardImage)
            }
        }

        return nil
    }

    /// Tries to find the card name in the rules text when the title OCR was mangled.
    /// Cards often reference themselves by name (e.g., "Mishra's Factory becomes an...").
    private func matchByAlternativeNames(signals: OCRSignals, cardImage: CGImage) async -> Card? {
        // Collect potential card names from OCR text lines
        // Only check lines that look like they contain a card name (capitalize pattern, reasonable length)
        var attempts = 0
        // Reduced from 20 → 10 — more attempts = more chances for
        // false positives from rules text or flavor text fragments.
        let maxAttempts = 10

        for result in signals.scanResults {
            guard attempts < maxAttempts else { break }

            let text = result.recognizedText
            let lower = text.lowercased()

            // Skip lines that are game mechanics — never contain card names
            if lower.contains("•") || lower.contains("*:") || lower.contains("+1/")
                || lower.contains("until end of turn") || lower.contains("protection from")
                || lower.contains("first strike") || lower.contains("summon")
                || lower.contains("illus") || lower.contains("wizard") { continue }

            let words = text.split(separator: " ")
            guard words.count >= 2 else { continue }

            // Try 2-4 word sequences at every position within the line
            for start in 0..<words.count {
              for length in stride(from: min(words.count - start, 4), through: 2, by: -1) {
                guard attempts < maxAttempts else { break }

                let candidate = words[start..<(start + length)].joined(separator: " ")
                guard candidate.count >= 5 else { continue }
                guard candidate.lowercased() != signals.cardName.lowercased() else { continue }

                // Skip candidates that are clearly rules text
                let candidateLower = candidate.lowercased()
                if candidateLower.contains("target") || candidateLower.contains("damage") || candidateLower.contains("discard") { continue }

                attempts += 1
                if let printings = try? await repository.findAllPrintings(name: candidate),
                   !printings.isEmpty {
                    print("[MTGScanner] Found card via rules text: '\(candidate)' (\(printings.count) printings)")

                    let correctedSignals = OCRSignals(
                        scanResults: signals.scanResults,
                        cardName: candidate,
                        collectorCandidates: signals.collectorCandidates,
                        artistName: signals.artistName,
                        copyrightYear: signals.copyrightYear,
                        hasOldTypeLine: signals.hasOldTypeLine,
                        detectedBorder: signals.detectedBorder
                    )
                    return await matchByMetadata(signals: correctedSignals, cardImage: cardImage)
                }
              }
            }
        }

        // Fuzzy name matching: OCR often mangles 1-3 characters
        // Strategy: gather candidates from multiple search approaches, then pick best Levenshtein match
        if signals.cardName.count >= 5 {
            var searchResults: [Card] = []

            // Approach 1: Full name search (substring match)
            if let results = try? await repository.searchCards(query: signals.cardName),
               !results.isEmpty {
                searchResults.append(contentsOf: results)
            }

            // Approach 2: Search by each word individually
            let words = signals.cardName.split(separator: " ").map(String.init)
            if searchResults.isEmpty {
                for word in words where word.count >= 4 {
                    if let results = try? await repository.searchCards(query: word),
                       !results.isEmpty {
                        searchResults.append(contentsOf: results)
                    }
                }
            }

            // Approach 3: For single-word names, try first 3-4 chars as prefix search
            // "Nacuralize" → search "Nac" won't work, but search "Natur" might via contains
            // Instead: try common OCR corrections on the name itself
            if searchResults.isEmpty && words.count == 1 {
                let name = signals.cardName
                // Try swapping common OCR confusions: c↔t, l↔i, m↔n, b↔h, o↔a
                let swaps: [(Character, Character)] = [
                    ("c", "t"), ("t", "c"), ("l", "i"), ("i", "l"),
                    ("m", "n"), ("n", "m"), ("b", "h"), ("h", "b"),
                    ("o", "a"), ("a", "o"), ("u", "n"), ("n", "u"),
                ]
                for (from, to) in swaps {
                    let corrected = name.map { $0 == from ? to : $0 }
                    let correctedStr = String(corrected)
                    if correctedStr != name,
                       let results = try? await repository.searchCards(query: correctedStr),
                       !results.isEmpty {
                        searchResults.append(contentsOf: results)
                        break // Found candidates, stop trying swaps
                    }
                }
            }

            if !searchResults.isEmpty {
                let uniqueNames = Array(Set(searchResults.map(\.name)))
                let ocrLower = signals.cardName.lowercased()
                let ocrWordCount = words.count
                var bestName: String?
                var bestScore = Int.max // Lower is better

                for name in uniqueNames {
                    let nameLower = name.lowercased()
                    let dist = levenshteinDistance(ocrLower, nameLower)
                    // Tightened from ≤4 → ≤3 to reduce false positives
                    // from rules text fragments matching unrelated cards.
                    guard dist <= 3 else { continue }

                    // Score: prefer names where OCR looks like a truncated/mangled version
                    // Bonus if OCR is a prefix of the candidate (common truncation pattern)
                    let isPrefix = nameLower.hasPrefix(String(ocrLower.prefix(min(ocrLower.count, 8))))
                    let prefixBonus = isPrefix ? -5 : 0

                    // Penalize names shorter than OCR (OCR rarely ADDS chars)
                    let lengthDiff = nameLower.count - ocrLower.count
                    let lengthPenalty = lengthDiff < 0 ? abs(lengthDiff) * 5 : lengthDiff
                    let score = dist * 2 + lengthPenalty + prefixBonus

                    if score < bestScore {
                        bestScore = score
                        bestName = name
                    }
                }

                if let matched = bestName {
                    let dist = levenshteinDistance(ocrLower, matched.lowercased())
                    print("[MTGScanner] Fuzzy match: '\(signals.cardName)' → '\(matched)' (distance: \(dist), score: \(bestScore))")
                    let correctedSignals = OCRSignals(
                        scanResults: signals.scanResults,
                        cardName: matched,
                        collectorCandidates: signals.collectorCandidates,
                        artistName: signals.artistName,
                        copyrightYear: signals.copyrightYear,
                        hasOldTypeLine: signals.hasOldTypeLine,
                        detectedBorder: signals.detectedBorder
                    )
                    return await matchByMetadata(signals: correctedSignals, cardImage: cardImage)
                }
            }
        }

        // Last resort: try searching by distinctive words from the title
        // "bymn to Tourach" → try "Tourach" as a DB search
        let commonWords: Set<String> = [
            "the", "of", "to", "and", "in", "for", "from", "with", "that", "this",
            "target", "player", "cards", "creature", "damage", "spell", "mana",
            "power", "until", "turn", "hand", "your", "their", "each", "all",
            "land", "artifact", "enchantment", "sorcery", "instant",
        ]
        let titleWords = signals.cardName.split(separator: " ")
        for word in titleWords.reversed() where word.count >= 6 {
            let searchWord = String(word)
            if commonWords.contains(searchWord.lowercased()) { continue }

            if let results = try? await repository.searchCards(query: searchWord),
               !results.isEmpty {
                // Count unique card names (not printings)
                let uniqueNames = Set(results.map(\.name))
                if uniqueNames.count <= 3, let bestMatch = results.first {
                    print("[MTGScanner] Found card via partial name search: '\(searchWord)' → '\(bestMatch.name)'")
                    let correctedSignals = OCRSignals(
                        scanResults: signals.scanResults,
                        cardName: bestMatch.name,
                        collectorCandidates: signals.collectorCandidates,
                        artistName: signals.artistName,
                        copyrightYear: signals.copyrightYear,
                        hasOldTypeLine: signals.hasOldTypeLine,
                        detectedBorder: signals.detectedBorder
                    )
                    return await matchByMetadata(signals: correctedSignals, cardImage: cardImage)
                }
            }
        }

        print("[MTGScanner] Alternative name search exhausted (\(attempts) attempts)")
        return nil
    }

    /// Strips leading zeros from a collector number so "015" matches "15".
    /// Preserves letter suffixes: "080a" → "80a".
    private func normalizeCollectorNumber(_ s: String) -> String {
        var result = s
        while result.count > 1 && result.hasPrefix("0") {
            result = String(result.dropFirst())
        }
        return result
    }

    /// Step 3a: Match by collector number (+ optional set code).
    private func matchByCollectorNumber(signals: OCRSignals) async -> Card? {
        guard !signals.collectorCandidates.isEmpty else { return nil }

        let printings = try? await repository.findAllPrintings(name: signals.cardName)
        guard let printings, !printings.isEmpty else { return nil }

        print("[MTGScanner] Collector candidates: \(signals.collectorCandidates.map { "set=\($0.setCode ?? "nil") num=\($0.collectorNumber)" })")

        // Try set code + collector number first (normalized for leading zeros)
        for candidate in signals.collectorCandidates {
            guard let setCode = candidate.setCode, !candidate.collectorNumber.isEmpty else { continue }
            let lowerCode = setCode.lowercased()
            let num = normalizeCollectorNumber(candidate.collectorNumber)
            let match = printings.first { (c: Card) in
                c.set.code == lowerCode && normalizeCollectorNumber(c.collectorNumber) == num
            }
            if let match {
                print("[MTGScanner] ✓ Matched by set+number: \(match.set.name) #\(match.collectorNumber)")
                return match
            }
        }

        // Try collector number only (normalized)
        for candidate in signals.collectorCandidates {
            guard !candidate.collectorNumber.isEmpty else { continue }
            let num = normalizeCollectorNumber(candidate.collectorNumber)
            let match = printings.first { normalizeCollectorNumber($0.collectorNumber) == num }
            if let match {
                print("[MTGScanner] ✓ Matched by number only: \(match.set.name) #\(match.collectorNumber)")
                return match
            }
        }

        return nil
    }

    /// Steps 3b-e: Metadata filtering, priority sort, image comparison.
    private func matchByMetadata(signals: OCRSignals, cardImage: CGImage) async -> Card? {
        guard var printings = try? await repository.findAllPrintings(name: signals.cardName),
              !printings.isEmpty else { return nil }

        print("[MTGScanner] All printings for '\(signals.cardName)': \(printings.count)")

        // NOTE: FP cache intentionally NOT used for printing resolution.
        // The cache may store a stale/wrong printing. Always resolve fresh
        // via metadata filtering + frame-masked image comparison.

        // Filter by artist (fuzzy — match any word with ≤1 char difference)
        if let artistName = signals.artistName {
            let ocrWords = Set(artistName.lowercased().split(separator: " ").map(String.init))
            let filtered = printings.filter { card in
                guard let a = card.artist else { return false }
                let dbWords = Set(a.lowercased().split(separator: " ").map(String.init))
                // Match if at least 1 significant word (length ≥ 4) is shared or close
                for ocrWord in ocrWords where ocrWord.count >= 4 {
                    for dbWord in dbWords where dbWord.count >= 4 {
                        if ocrWord == dbWord { return true }
                        // Allow 1 character difference (e.g., "kaje" vs "kaja")
                        if ocrWord.count == dbWord.count && levenshteinClose(ocrWord, dbWord) {
                            return true
                        }
                    }
                }
                return false
            }
            if !filtered.isEmpty {
                printings = filtered
                print("[MTGScanner] After artist filter: \(printings.count)")
            }
        }

        // Filter by copyright year (±1 tolerance: copyright may differ from release date)
        if let year = signals.copyrightYear {
            let validYears = Set([String(year - 1), String(year), String(year + 1)])
            let filtered = printings.filter { card in
                guard let rel = card.releasedAt, rel.count >= 4 else { return false }
                return validYears.contains(String(rel.prefix(4)))
            }
            if !filtered.isEmpty {
                printings = filtered
                print("[MTGScanner] After year filter (\(year)±1): \(printings.count)")
            }
        }

        // Filter by old frame ("Summon" type line = pre-1999)
        if signals.hasOldTypeLine {
            let oldFrames: Set<String> = ["1993", "1997"]
            let filtered = printings.filter { card in
                guard let f = card.frame else { return false }
                return oldFrames.contains(f)
            }
            if !filtered.isEmpty {
                printings = filtered
                print("[MTGScanner] After old-frame filter: \(printings.count)")
            }
        }

        // Filter by border color (only for clear black/white — "borderless" is unreliable)
        if let border = signals.detectedBorder, border == .black || border == .white {
            let filtered = printings.filter { $0.borderColor == border.rawValue }
            if !filtered.isEmpty {
                printings = filtered
                print("[MTGScanner] After border filter (\(border.rawValue)): \(printings.count)")
            }
        }

        // Sort by printing preference. Four-tier stable sort:
        // 1. Set type priority (expansion > core > masters > ...)
        // 2. Release date DESCENDING (newest first — users are more
        //    likely to own recent printings in current circulation
        //    than decade-old ones. "Oldest first" was actively wrong
        //    for cards like Thermo-Alchemist where Eldritch Moon 2016
        //    was picked over the user's actual Midnight Hunt 2021.)
        // 3. Collector number ascending (within the same set, the
        //    regular version has a low number like #51, while
        //    borderless/showcase/extended-art variants have high
        //    numbers like #350.)
        // 4. Set name alphabetical (final tiebreak for determinism)
        printings.sort { a, b in
            let pa = printingPriority(a)
            let pb = printingPriority(b)
            if pa != pb { return pa < pb }
            // Newest first: "9999" default → sorts last (unknown date)
            let da = a.releasedAt ?? "0000"
            let db = b.releasedAt ?? "0000"
            if da != db { return da > db }
            // Within the same set+date: lower collector number = regular version
            let na = Int(a.collectorNumber.filter(\.isNumber)) ?? 9999
            let nb = Int(b.collectorNumber.filter(\.isNumber)) ?? 9999
            if na != nb { return na < nb }
            return a.set.name < b.set.name
        }

        if printings.count == 1, let match = printings.first {
            print("[MTGScanner] ✓ Matched by metadata (unique): \(match.set.name) #\(match.collectorNumber)")
            return match
        }

        // Multiple candidates — use frame-masked comparison (art masked out)
        if printings.count > 1 {
            printings = Array(printings.prefix(8))
            print("[MTGScanner] \(printings.count) candidates remain, comparing frames...")
            if let match = await resolveByFrameComparison(source: cardImage, printings: printings) {
                print("[MTGScanner] ✓ Matched by frame: \(match.set.name) #\(match.collectorNumber)")
                return match
            }
            if let match = printings.first {
                print("[MTGScanner] Using priority preference: \(match.set.name)")
                return match
            }
        }

        // Fallback
        if let match = printings.first {
            return match
        }
        print("[MTGScanner] Falling back to name-only lookup")
        return try? await repository.identifyCard(name: signals.cardName)
    }

    // MARK: - Step 4: Art Variant Resolution

    /// Checks if the identified card has art variants in the same set,
    /// and resolves to the correct one by comparing art regions.
    private func resolveArtVariant(card: Card, cardImage: CGImage) async -> Card {
        do {
            let variants = try await repository.findVariants(name: card.name, setCode: card.set.code)
            guard variants.count > 1 else { return card }

            // Only compare variants with genuinely different art (different illustrationID).
            // Variants that share the same illustration but differ in frame treatment
            // (regular vs extended-art vs borderless vs showcase) must NOT override
            // the printing already resolved by resolveExactPrinting, because the
            // extended-art/borderless art_crop is larger and wins VNFeaturePrint
            // comparison even though the user holds the regular version.
            let distinctIllustrations = Set(variants.compactMap(\.illustrationID))
            guard distinctIllustrations.count > 1 else {
                print("[MTGScanner] Art variants in \(card.set.name) share same illustration — keeping resolved #\(card.collectorNumber)")
                return card
            }

            // Multiple distinct illustrations exist — compare art to pick the right one.
            // But preserve the exact printing (frame treatment) within that illustration:
            // first find which illustrationID matches, then keep the already-resolved
            // printing if it has that illustrationID.
            print("[MTGScanner] Found \(variants.count) art variants (\(distinctIllustrations.count) distinct illustrations) in \(card.set.name), comparing art...")
            if let match = await artVariantMatcher.matchVariant(cardImage: cardImage, variants: variants) {
                // If the matched variant has the same illustrationID as our already-resolved
                // card, keep the original (its collector# was chosen by OCR signals).
                if match.illustrationID == card.illustrationID {
                    print("[MTGScanner] ✓ Art variant confirms illustration, keeping #\(card.collectorNumber)")
                    return card
                }
                print("[MTGScanner] ✓ Art variant matched: #\(match.collectorNumber)")
                return match
            }
        } catch {
            // Variant lookup failed, return original
        }
        return card
    }

    // MARK: - Frame-Masked Comparison

    /// Resolves the correct printing by comparing frame chrome only.
    ///
    /// Downloads reference images for each candidate, masks the art region
    /// (identical across printings) on both source and reference, then uses
    /// VNFeaturePrint to compare. Optionally combines with set-symbol-region
    /// distance (40% weight) for stronger discrimination.
    ///
    /// This is the primary printing-resolution method — it replaces full-card
    /// image comparison which was dominated by art similarity.
    private func resolveByFrameComparison(source: CGImage, printings: [Card]) async -> Card? {
        var candidateImages: [(index: Int, image: CGImage)] = []

        for (index, card) in printings.enumerated() {
            guard let urlString = card.imageURIs["normal"] ?? card.imageURIs["small"] else { continue }
            if let image = await imageMatcher.downloadImage(from: urlString) {
                candidateImages.append((index, image))
            }
        }

        guard !candidateImages.isEmpty else { return nil }

        // Compute symbol distances for weighted comparison
        let scanResults = (try? await recognizer.recognizeText(in: source)) ?? []
        let symbolMatcher = SetSymbolMatcher()
        let symDists = await symbolMatcher.symbolDistances(
            sourceImage: source,
            candidateImages: candidateImages,
            scanResults: scanResults
        )

        let images = candidateImages.map(\.image)
        guard let bestIdx = await imageMatcher.findBestMatchByFrame(
            for: source,
            among: images,
            symbolDistances: symDists
        ) else {
            return nil
        }

        let originalIndex = candidateImages[bestIdx].index
        let result = printings[originalIndex]
        print("[MTGScanner] Frame comparison selected: \(result.set.name) #\(result.collectorNumber)")
        return result
    }

    // MARK: - Printing Priority

    /// Returns a priority score for a card's printing (lower = preferred).
    /// Regular expansions/core sets preferred over foreign variants and promos.
    private func printingPriority(_ card: Card) -> Int {
        let setName = card.set.name.lowercased()
        let setCode = card.set.code.lowercased()

        // Explicit deprioritization of known supplemental-reprint
        // products that commonly win ties against the original
        // expansion printing when metadata is weak.
        if setName.contains("foreign") || setName.contains("fbb") {
            return 9
        }
        // "The List" / "The List" promo sheets (Scryfall code "plst")
        if setCode == "plst" || setName.contains("the list") {
            return 8
        }
        // Universes Beyond crossover sets (Fallout, LotR, Warhammer, etc.)
        // are commonly misidentified for non-crossover cards.
        let crossoverSets = ["pip", "ltr", "ltc", "40k", "who", "acr"]
        if crossoverSets.contains(setCode) {
            return 7
        }

        switch card.set.setType {
        case "expansion": return 0
        case "core": return 1
        case "draft_innovation": return 2
        case "masters": return 3
        case "commander": return 4
        case "starter": return 5
        case "duel_deck": return 6
        case "promo": return 7
        case "memorabilia": return 8
        default: return 6
        }
    }

    /// Checks if two strings of equal length differ by at most 1 character.
    /// True if every printing of this card is a token (no mana cost,
    /// "Token" in type line). Used to skip type-line fragments like
    /// "Human Cleric" that match real token cards in the DB but are
    /// actually the subtype text from a creature (Dawnbringer Cleric).
    private func isTokenOnly(_ printings: [Card]) -> Bool {
        printings.allSatisfy { card in
            let tl = card.typeLine.lowercased()
            let noMana = card.manaCost == nil || card.manaCost?.isEmpty == true
            return tl.contains("token") || noMana
        }
    }

    private func levenshteinClose(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        var diffs = 0
        for (c1, c2) in zip(a, b) {
            if c1 != c2 { diffs += 1 }
            if diffs > 1 { return false }
        }
        return diffs <= 1
    }

    /// Computes full Levenshtein edit distance between two strings.
    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,      // deletion
                    curr[j-1] + 1,    // insertion
                    prev[j-1] + cost  // substitution
                )
            }
            prev = curr
        }

        return prev[n]
    }
}
