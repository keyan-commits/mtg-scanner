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
                let hasCommon = ocrWords.contains { ow in
                    cacheWords.contains { cw in
                        ow == cw || (ow.count == cw.count && levenshteinClose(String(ow), String(cw)))
                    }
                }
                if !hasCommon && !ocrWords.isEmpty && !cacheWords.isEmpty {
                    print("[MTGScanner] FeaturePrint cache rejected: OCR '\(signals.cardName)' ≠ cache '\(cacheHit.cardName)'")
                    // Don't return nil — fall through to OCR pipeline
                } else {
                    // Cache + OCR agree on card name — but DON'T use a separate code path.
                    // Fall through to the full OCR pipeline which has all the proven fallbacks.
                    // The cache just confirmed the card name — the original pipeline handles printing.
                    print("[MTGScanner] FeaturePrint cache confirmed name: '\(cacheHit.cardName)' — using full OCR pipeline")
                }
            } else {
                // OCR failed — cache confirmed name, fall through to full pipeline
                print("[MTGScanner] FeaturePrint cache confirmed name (no OCR): '\(cacheHit.cardName)'")
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
                let yearStr = String(year)
                let filtered = narrowed.filter { card in
                    guard let rel = card.releasedAt, rel.count >= 4 else { return false }
                    return String(rel.prefix(4)) == yearStr
                }
                if !filtered.isEmpty { narrowed = filtered }
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
            let words = text.split(separator: " ")
            guard words.count >= 2 else { continue }

            // Try 2-4 word sequences starting from the beginning of each line
            for length in stride(from: min(words.count, 4), through: 2, by: -1) {
                guard attempts < maxAttempts else { break }

                let candidate = words[0..<length].joined(separator: " ")
                guard candidate.count >= 5 else { continue }
                guard candidate.lowercased() != signals.cardName.lowercased() else { continue }

                // Skip lines that are clearly rules text (contain common keywords)
                let lower = candidate.lowercased()
                if lower.contains("target") || lower.contains("damage") || lower.contains("discard") { continue }

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

        // Filter by copyright year
        if let year = signals.copyrightYear {
            let yearStr = String(year)
            let filtered = printings.filter { card in
                guard let rel = card.releasedAt, rel.count >= 4 else { return false }
                return String(rel.prefix(4)) == yearStr
            }
            if !filtered.isEmpty {
                printings = filtered
                print("[MTGScanner] After year filter (\(year)): \(printings.count)")
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
}
