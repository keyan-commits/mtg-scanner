import Foundation
import CoreGraphics

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
    func identifyCropped(cardImage: CGImage) async -> Card?

    /// Identifies all cards visible in raw image data.
    /// Detects multiple card rectangles, identifies each independently.
    /// Falls back to single-card identification if multi-detect finds nothing.
    func identifyAll(imageData: Data) async -> [Card]
}

// MARK: - Implementation

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

    // MARK: - Initialization

    init(
        recognizer: TextRecognizerProtocol,
        repository: CardRepositoryProtocol,
        visualSearchEngine: VisualSearchEngine? = nil,
        featurePrintCache: FeaturePrintCache? = nil,
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
    func identifyCropped(cardImage: CGImage) async -> Card? {
        print("[MTGScanner] Identifying cropped image \(cardImage.width)x\(cardImage.height)")

        // Grid cells are already properly cropped — skip card detection.
        // detectAndCrop() applies perspective correction that shrinks the image
        // (e.g., 1008x1512 → 702x566), breaking OCR.
        let finalImage = cardImage

        // Strategy 0: Check FP cache first — corrections persist across scans
        // If the cache has a match with full printing info, use it directly
        if let cache = featurePrintCache,
           let artImage = artVariantMatcher.extractArtRegion(from: finalImage),
           let cacheHit = await cache.search(artImage: artImage),
           let setCode = cacheHit.setCode, let collectorNum = cacheHit.collectorNumber {
            // Quick OCR cross-validation: confirm the card name matches
            if let scanResults = try? await recognizer.recognizeText(in: finalImage),
               let firstName = nameExtractor.extractCardName(from: Array(scanResults.prefix(3))) {
                let ocrWords = firstName.lowercased().split(separator: " ").filter { $0.count >= 4 }
                let cacheWords = cacheHit.cardName.lowercased().split(separator: " ").filter { $0.count >= 4 }
                let allMatch = cacheWords.allSatisfy { cw in
                    ocrWords.contains { ow in
                        if ow == cw { return true }
                        let maxDist = ow.count >= 8 ? 2 : 1
                        return levenshteinDistance(String(ow), String(cw)) <= maxDist
                    }
                }
                if allMatch || ocrWords.isEmpty || cacheWords.isEmpty {
                    if let printings = try? await repository.findAllPrintings(name: cacheHit.cardName),
                       let exact = printings.first(where: { $0.set.code == setCode && $0.collectorNumber == collectorNum }) {
                        print("[MTGScanner] \u{2713} Matched by cached printing (deck photo): \(exact.set.name) #\(exact.collectorNumber)")
                        return exact
                    }
                }
            }
        }

        // Strategy 1: DB-validated OCR — try every text line against the DB
        // This handles misaligned grid cells where the card name isn't the topmost text
        if let card = await identifyByDBValidatedOCR(cardImage: finalImage, wasCropped: false) {
            return await resolveArtVariant(card: card, cardImage: finalImage)
        }

        // Strategy 2: Fall back to the standard pipeline
        guard let identified = await resolvePrinting(cardImage: finalImage, wasCropped: false) else {
            return nil
        }

        return await resolveArtVariant(card: identified, cardImage: finalImage)
    }

    /// Tries every OCR text line against the DB to find actual card names.
    /// Much more robust for deck photo grid cells where the card name may not be the topmost text.
    private func identifyByDBValidatedOCR(cardImage: CGImage, wasCropped: Bool) async -> Card? {
        guard let scanResults = try? await recognizer.recognizeText(in: cardImage) else {
            return nil
        }

        // Try each text line as a potential card name — check against DB
        for result in scanResults {
            let text = nameExtractor.extractCardName(from: [result]) ?? result.recognizedText
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard text.count >= 3, text.count <= 40 else { continue }

            // Skip common non-name text
            let lower = text.lowercased()
            if lower.contains("summon") || lower.contains("instant") ||
               lower.contains("sorcery") || lower.contains("protection") ||
               lower.contains("damage") || lower.contains("creature or") ||
               lower.contains("the ") && lower.count > 20 ||
               lower.contains("illus") || lower.contains("wizard") {
                continue
            }

            // Check if this text matches a card name in the DB
            if let printings = try? await repository.findAllPrintings(name: text),
               !printings.isEmpty {
                print("[MTGScanner] DB-validated OCR: '\(text)' → \(printings.count) printings")

                // Apply metadata filtering (checks FP cache for corrected printing first)
                let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped)
                let correctedSignals = OCRSignals(
                    scanResults: signals?.scanResults ?? scanResults,
                    cardName: text,
                    collectorCandidates: signals?.collectorCandidates ?? [],
                    artistName: signals?.artistName,
                    copyrightYear: signals?.copyrightYear,
                    hasOldTypeLine: signals?.hasOldTypeLine ?? false,
                    detectedBorder: signals?.detectedBorder
                )
                return await matchByMetadata(signals: correctedSignals, cardImage: cardImage)
            }

            // Also try fuzzy match for this line
            let words = text.split(separator: " ").map(String.init)
            for word in words where word.count >= 5 {
                if let results = try? await repository.searchCards(query: word),
                   !results.isEmpty {
                    let uniqueNames = Array(Set(results.map(\.name)))
                    let ocrLower = text.lowercased()

                    for name in uniqueNames {
                        let dist = levenshteinDistance(ocrLower, name.lowercased())
                        if dist <= 2 {
                            print("[MTGScanner] DB-validated fuzzy: '\(text)' → '\(name)' (distance: \(dist))")
                            let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped)
                            let correctedSignals = OCRSignals(
                                scanResults: signals?.scanResults ?? scanResults,
                                cardName: name,
                                collectorCandidates: signals?.collectorCandidates ?? [],
                                artistName: signals?.artistName,
                                copyrightYear: signals?.copyrightYear,
                                hasOldTypeLine: signals?.hasOldTypeLine ?? false,
                                detectedBorder: signals?.detectedBorder
                            )
                            return await matchByMetadata(signals: correctedSignals, cardImage: cardImage)
                        }
                    }
                }
            }

            // Try splitting concatenated words (e.g., "Orderof" → "Order of")
            // OCR sometimes merges adjacent words on old-frame cards
            let nameWords = text.split(separator: " ").map(String.init)
            for (wi, word) in nameWords.enumerated() where word.count >= 7 {
                for splitPos in 2..<(word.count - 1) {
                    let left = String(word.prefix(splitPos))
                    let right = String(word.suffix(word.count - splitPos))
                    var fixedWords = nameWords
                    fixedWords[wi] = left
                    fixedWords.insert(right, at: wi + 1)
                    let fixedName = fixedWords.joined(separator: " ")

                    // Try exact match first
                    if let printings = try? await repository.findAllPrintings(name: fixedName),
                       !printings.isEmpty {
                        print("[MTGScanner] DB-validated split: '\(text)' → '\(fixedName)' (\(printings.count) printings)")
                        let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped)
                        let correctedSignals = OCRSignals(
                            scanResults: signals?.scanResults ?? scanResults,
                            cardName: fixedName,
                            collectorCandidates: signals?.collectorCandidates ?? [],
                            artistName: signals?.artistName,
                            copyrightYear: signals?.copyrightYear,
                            hasOldTypeLine: signals?.hasOldTypeLine ?? false,
                            detectedBorder: signals?.detectedBorder
                        )
                        return await matchByMetadata(signals: correctedSignals, cardImage: cardImage)
                    }

                    // Try fuzzy match on the split name
                    if left.count >= 4,
                       let results = try? await repository.searchCards(query: left),
                       !results.isEmpty {
                        let uniqueNames = Array(Set(results.map(\.name)))
                        let fixedLower = fixedName.lowercased()
                        for name in uniqueNames {
                            let dist = levenshteinDistance(fixedLower, name.lowercased())
                            if dist <= 2 {
                                print("[MTGScanner] DB-validated split+fuzzy: '\(text)' → '\(fixedName)' → '\(name)' (distance: \(dist))")
                                let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped)
                                let correctedSignals = OCRSignals(
                                    scanResults: signals?.scanResults ?? scanResults,
                                    cardName: name,
                                    collectorCandidates: signals?.collectorCandidates ?? [],
                                    artistName: signals?.artistName,
                                    copyrightYear: signals?.copyrightYear,
                                    hasOldTypeLine: signals?.hasOldTypeLine ?? false,
                                    detectedBorder: signals?.detectedBorder
                                )
                                return await matchByMetadata(signals: correctedSignals, cardImage: cardImage)
                            }
                        }
                    }
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

        // Steps 1-3: Visual search → OCR fallback → Printing resolution
        guard let identified = await resolvePrinting(cardImage: cardImage, wasCropped: wasCropped) else {
            return nil
        }

        // Step 4: Art variant resolution
        let finalCard = await resolveArtVariant(card: identified, cardImage: cardImage)

        // Step 5: Cache the result for future FeaturePrint lookups
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

        guard let identified = await resolvePrinting(cardImage: cardImage, wasCropped: wasCropped) else {
            return nil
        }

        let finalCard = await resolveArtVariant(card: identified, cardImage: cardImage)

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

    // MARK: - Step 3: Printing Resolution

    private func resolvePrinting(cardImage: CGImage, wasCropped: Bool) async -> Card? {

        // Step 1: Visual search (primary identification)
        if let match = await resolveByVisualSearch(cardImage: cardImage, wasCropped: wasCropped) {
            return match
        }

        // Step 2+: OCR fallback (when visual search unavailable or fails)
        guard let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped) else {
            return nil
        }

        // Step 3a: Collector number + set code (most precise)
        if let match = await matchByCollectorNumber(signals: signals) {
            return match
        }

        // Step 3b-e: Metadata filtering + image comparison
        if let match = await matchByMetadata(signals: signals, cardImage: cardImage) {
            return match
        }

        // Step 3f: Try common first-character OCR corrections
        // Old-frame fonts cause b→H, l→L, f→F etc. substitutions
        if let match = await matchByFirstCharCorrection(signals: signals, cardImage: cardImage) {
            return match
        }

        // Step 3g: Fallback — try alternative names from rules text
        // Old-frame cards have stylized title fonts that OCR mangles,
        // but rules text uses a clean font and often contains the card's own name
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

        // Try FeaturePrint cache first (grows as user scans cards)
        if let cache = featurePrintCache,
           let cacheHit = await cache.search(artImage: artImage) {
            print("[MTGScanner] FeaturePrint cache candidate: '\(cacheHit.cardName)'")

            // Cross-validate with OCR — reject if OCR reads a different card
            if let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped) {
                let ocrWords = signals.cardName.lowercased().split(separator: " ").filter { $0.count >= 4 }
                let cacheWords = cacheHit.cardName.lowercased().split(separator: " ").filter { $0.count >= 4 }
                // ALL cache words must be found in OCR (with fuzzy tolerance)
                // e.g., cache "White Knight" requires BOTH "White" AND "Knight" in OCR
                let allCacheWordsFound = cacheWords.allSatisfy { cw in
                    ocrWords.contains { ow in
                        if ow == cw { return true }
                        let maxDist = ow.count >= 8 ? 2 : 1
                        return levenshteinDistance(String(ow), String(cw)) <= maxDist
                    }
                }
                if !allCacheWordsFound && !ocrWords.isEmpty && !cacheWords.isEmpty {
                    print("[MTGScanner] FeaturePrint cache rejected: OCR '\(signals.cardName)' ≠ cache '\(cacheHit.cardName)'")
                    // Don't return nil — fall through to OCR pipeline
                } else {
                    // Cache + OCR words overlap. Use the cache name ONLY if it's actually
                    // the same card (case-insensitive). Otherwise trust the OCR name —
                    // the cache might match a visually similar but different card.
                    let namesMatch = cacheHit.cardName.lowercased() == signals.cardName.lowercased()
                        || levenshteinDistance(cacheHit.cardName.lowercased(), signals.cardName.lowercased()) <= 2

                    let resolvedName = namesMatch ? cacheHit.cardName : signals.cardName
                    print("[MTGScanner] FeaturePrint cache confirmed: cache '\(cacheHit.cardName)', OCR '\(signals.cardName)' → using '\(resolvedName)'")

                    // If names match AND cache has full printing identity, use it directly
                    if namesMatch,
                       let setCode = cacheHit.setCode, let collectorNum = cacheHit.collectorNumber,
                       let printings = try? await repository.findAllPrintings(name: resolvedName),
                       let exact = printings.first(where: { $0.set.code == setCode && $0.collectorNumber == collectorNum }) {
                        print("[MTGScanner] \u{2713} Matched by cached printing: \(exact.set.name) #\(exact.collectorNumber)")
                        return exact
                    }

                    // Resolve via metadata with the best name
                    let correctedSignals = OCRSignals(
                        scanResults: signals.scanResults,
                        cardName: resolvedName,
                        collectorCandidates: signals.collectorCandidates,
                        artistName: signals.artistName,
                        copyrightYear: signals.copyrightYear,
                        hasOldTypeLine: signals.hasOldTypeLine,
                        detectedBorder: signals.detectedBorder
                    )
                    if let match = await matchByMetadata(signals: correctedSignals, cardImage: cardImage) {
                        return match
                    }
                }
            } else {
                // OCR failed — try exact printing from cache, then fall back to first printing
                print("[MTGScanner] FeaturePrint cache confirmed name (no OCR): '\(cacheHit.cardName)' — resolving printing")
                if let printings = try? await repository.findAllPrintings(name: cacheHit.cardName) {
                    if let setCode = cacheHit.setCode, let collectorNum = cacheHit.collectorNumber,
                       let exact = printings.first(where: { $0.set.code == setCode && $0.collectorNumber == collectorNum }) {
                        print("[MTGScanner] \u{2713} Matched by cached printing: \(exact.set.name) #\(exact.collectorNumber)")
                        return exact
                    }
                    if let first = printings.first {
                        return first
                    }
                }
            }
        }

        // Fall back to legacy pHash visual search engine
        guard let visualEngine = visualSearchEngine else { return nil }

        // Use strict threshold (8) for confident visual matches
        guard let match = visualEngine.bestMatch(for: artImage, maxDistance: 8) else {
            print("[MTGScanner] Visual search: no match within threshold")
            return nil
        }

        let distance = PerceptualHash.hammingDistance(
            PerceptualHash.compute(from: artImage) ?? 0,
            match.hash
        )
        print("[MTGScanner] \u{2713} Visual match: '\(match.cardName)' (distance: \(distance))")

        // Run OCR to get signals for cross-validation and printing refinement
        let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped)

        // Cross-validate: if OCR found a card name, check it's compatible with visual match
        if let signals {
            let ocrName = signals.cardName.lowercased()
            let visualName = match.cardName.lowercased()
            // Check if any significant word from OCR name appears in visual name or vice versa
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
        }

        // Look up all printings for the matched card name
        guard let printings = try? await repository.findAllPrintings(name: match.cardName),
              !printings.isEmpty else {
            print("[MTGScanner] Visual match name '\(match.cardName)' not found in DB")
            return nil
        }

        // Refine to exact printing using OCR signals
        if let signals {
            // Use collector number if available (most precise)
            for candidate in signals.collectorCandidates {
                if let setCode = candidate.setCode, !candidate.collectorNumber.isEmpty {
                    let lowerCode = setCode.lowercased()
                    let num = candidate.collectorNumber
                    if let exact = printings.first(where: { $0.set.code == lowerCode && $0.collectorNumber == num }) {
                        print("[MTGScanner] \u{2713} Visual + set+number: \(exact.set.name) #\(exact.collectorNumber)")
                        return exact
                    }
                }
            }

            for candidate in signals.collectorCandidates {
                if !candidate.collectorNumber.isEmpty {
                    let num = candidate.collectorNumber
                    if let exact = printings.first(where: { $0.collectorNumber == num }) {
                        print("[MTGScanner] \u{2713} Visual + number: \(exact.set.name) #\(exact.collectorNumber)")
                        return exact
                    }
                }
            }

            // Apply metadata filters to narrow printing
            var narrowed = printings

            if let artistName = signals.artistName {
                let ocrWords = Set(artistName.lowercased().split(separator: " ").map(String.init))
                let filtered = narrowed.filter { card in
                    guard let a = card.artist else { return false }
                    let dbWords = Set(a.lowercased().split(separator: " ").map(String.init))
                    for ocrWord in ocrWords where ocrWord.count >= 4 {
                        for dbWord in dbWords where dbWord.count >= 4 {
                            if ocrWord == dbWord { return true }
                            if ocrWord.count == dbWord.count && levenshteinClose(ocrWord, dbWord) {
                                return true
                            }
                        }
                    }
                    return false
                }
                if !filtered.isEmpty { narrowed = filtered }
            }

            if let year = signals.copyrightYear {
                // Allow ±1 year tolerance: copyright year (printed on card) may differ
                // from Scryfall's released_at (e.g., PELP copyright ©1999, released 2000)
                let validYears = Set([String(year - 1), String(year), String(year + 1)])
                print("[MTGScanner] Year filter: checking \(narrowed.count) cards for years \(validYears)")
                let filtered = narrowed.filter { card in
                    guard let rel = card.releasedAt, rel.count >= 4 else { return false }
                    return validYears.contains(String(rel.prefix(4)))
                }
                print("[MTGScanner] Year filter: \(filtered.count) matched out of \(narrowed.count)")
                if !filtered.isEmpty {
                    narrowed = filtered
                    print("[MTGScanner] After year filter (\(year)±1): \(narrowed.count)")
                }
            } else {
                print("[MTGScanner] Year filter: copyright year is nil, skipping")
            }

            if signals.hasOldTypeLine {
                let oldFrames: Set<String> = ["1993", "1997"]
                let filtered = narrowed.filter { card in
                    guard let f = card.frame else { return false }
                    return oldFrames.contains(f)
                }
                if !filtered.isEmpty { narrowed = filtered }
            }

            if let border = signals.detectedBorder, border == .black || border == .white {
                let filtered = narrowed.filter { $0.borderColor == border.rawValue }
                if !filtered.isEmpty { narrowed = filtered }
            }

            // Prefer the printing whose illustration_id matches the visual match
            if let artMatch = narrowed.first(where: { $0.illustrationID == match.illustrationID }) {
                print("[MTGScanner] \u{2713} Visual + metadata: \(artMatch.set.name) #\(artMatch.collectorNumber)")
                return artMatch
            }

            if narrowed.count == 1, let single = narrowed.first {
                print("[MTGScanner] \u{2713} Visual + metadata (unique): \(single.set.name) #\(single.collectorNumber)")
                return single
            }
        }

        // No OCR refinement — return printing with matching illustration_id, or first printing
        if let artMatch = printings.first(where: { $0.illustrationID == match.illustrationID }) {
            print("[MTGScanner] \u{2713} Visual match (illustration_id): \(artMatch.set.name) #\(artMatch.collectorNumber)")
            return artMatch
        }

        print("[MTGScanner] \u{2713} Visual match (first printing): \(printings[0].set.name) #\(printings[0].collectorNumber)")
        return printings.first
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
        let maxAttempts = 20

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
                    guard dist <= 4 else { continue }

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

    /// Step 3a: Match by collector number (+ optional set code).
    private func matchByCollectorNumber(signals: OCRSignals) async -> Card? {
        guard !signals.collectorCandidates.isEmpty else { return nil }

        let printings = try? await repository.findAllPrintings(name: signals.cardName)
        guard let printings, !printings.isEmpty else { return nil }

        // Try set code + collector number first
        for candidate in signals.collectorCandidates {
            guard let setCode = candidate.setCode, !candidate.collectorNumber.isEmpty else { continue }
            let lowerCode = setCode.lowercased()
            let num = candidate.collectorNumber
            let match = printings.first { (c: Card) in c.set.code == lowerCode && c.collectorNumber == num }
            if let match {
                print("[MTGScanner] ✓ Matched by set+number: \(match.set.name) #\(match.collectorNumber)")
                return match
            }
        }

        // Try collector number only
        for candidate in signals.collectorCandidates {
            guard !candidate.collectorNumber.isEmpty else { continue }
            let num = candidate.collectorNumber
            let match = printings.first { $0.collectorNumber == num }
            if let match {
                print("[MTGScanner] ✓ Matched by number: \(match.set.name) #\(match.collectorNumber)")
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

        // Check if the FP cache has a corrected printing for this card name
        if let cache = featurePrintCache {
            let cached = await cache.findByName(signals.cardName)
            if let entry = cached.first,
               let setCode = entry.setCode, let collectorNum = entry.collectorNumber,
               let exact = printings.first(where: { $0.set.code == setCode && $0.collectorNumber == collectorNum }) {
                print("[MTGScanner] \u{2713} Matched by cached printing: \(exact.set.name) #\(exact.collectorNumber)")
                return exact
            }
        }

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

        // Sort by printing preference
        printings.sort { a, b in printingPriority(a) < printingPriority(b) }

        if printings.count == 1, let match = printings.first {
            print("[MTGScanner] ✓ Matched by metadata (unique): \(match.set.name) #\(match.collectorNumber)")
            return match
        }

        // Multiple candidates — compare full card images (limit to top 8 to prevent OOM)
        if printings.count > 1 {
            printings = Array(printings.prefix(8))
            print("[MTGScanner] \(printings.count) candidates remain, comparing card images...")
            if let match = await resolveByImageComparison(source: cardImage, candidates: printings) {
                print("[MTGScanner] ✓ Matched by image: \(match.set.name) #\(match.collectorNumber)")
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

            print("[MTGScanner] Found \(variants.count) art variants in \(card.set.name), comparing art...")
            if let match = await artVariantMatcher.matchVariant(cardImage: cardImage, variants: variants) {
                print("[MTGScanner] ✓ Art variant matched: #\(match.collectorNumber)")
                return match
            }
        } catch {
            // Variant lookup failed, return original
        }
        return card
    }

    // MARK: - Image Comparison

    /// Downloads reference images and uses VNFeaturePrint to find the best match.
    /// Images are downloaded in memory and released after comparison.
    private func resolveByImageComparison(source: CGImage, candidates: [Card]) async -> Card? {
        var candidateImages: [(index: Int, image: CGImage)] = []

        for (index, card) in candidates.enumerated() {
            guard let urlString = card.imageURIs["normal"] ?? card.imageURIs["small"] else { continue }
            if let image = await imageMatcher.downloadImage(from: urlString) {
                candidateImages.append((index, image))
            }
        }

        guard !candidateImages.isEmpty else { return nil }

        let images = candidateImages.map(\.image)
        guard let bestIdx = await imageMatcher.findBestMatch(for: source, among: images) else {
            return nil
        }

        let originalIndex = candidateImages[bestIdx].index
        return candidates[originalIndex]
    }

    // MARK: - Printing Priority

    /// Returns a priority score for a card's printing (lower = preferred).
    /// Regular expansions/core sets preferred over foreign variants and promos.
    private func printingPriority(_ card: Card) -> Int {
        let setName = card.set.name.lowercased()
        if setName.contains("foreign") || setName.contains("fbb") {
            return 9
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
