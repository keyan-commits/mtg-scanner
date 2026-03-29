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
// │  Step 1: OCR Signal Extraction                                  │
// │    - Card name (topmost text via CardNameExtractor)             │
// │    - Collector number + set code (bottom text)                  │
// │    - Artist name (from "Illus." line)                           │
// │    - Copyright end year (from "©YYYY" or "©YYYY-YYYY")         │
// │    - Old frame detection ("Summon" type line = pre-1999)        │
// │    - Border color (pixel sampling on cropped card)              │
// │                                                                 │
// │  Step 2: Printing Resolution (most precise first)               │
// │    2a. Set code + collector number → exact printing             │
// │    2b. Collector number only → match among all printings        │
// │    2c. Metadata filtering: artist → year → frame → border      │
// │    2d. Printing priority sort (expansion > core > promo)        │
// │    2e. VNFeaturePrint image comparison (tiebreaker)             │
// │                                                                 │
// │  Step 3: Art Variant Resolution                                 │
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

    // MARK: - Initialization

    init(
        recognizer: TextRecognizerProtocol,
        repository: CardRepositoryProtocol,
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

        // Step 1-2: OCR + Printing resolution
        guard let identified = await resolvePrinting(cardImage: cardImage, wasCropped: wasCropped) else {
            return nil
        }

        // Step 3: Art variant resolution
        return await resolveArtVariant(card: identified, cardImage: cardImage)
    }

    /// Identifies all cards visible in the image data.
    ///
    /// Detects multiple card rectangles, perspective-corrects each,
    /// and runs the full identification pipeline on each card independently.
    /// Falls back to single-card identification if multi-detect finds nothing.
    func identifyAll(imageData: Data) async -> [Card] {
        guard let rawImage = imageProcessor.downsample(data: imageData) else {
            return []
        }

        // Detect and crop all cards (handles subdividing wide multi-card rectangles)
        let croppedCards = cardDetector.detectAndCropAllCards(from: rawImage)
        print("[MTGScanner] Multi-card detection: found \(croppedCards.count) cards")

        if croppedCards.isEmpty {
            // Fallback to single-card detection
            if let card = await identify(imageData: imageData) {
                return [card]
            }
            return []
        }

        // Process one card at a time to control memory
        var results: [Card] = []
        for (index, cardImage) in croppedCards.enumerated() {
            print("[MTGScanner] Identifying card \(index + 1) of \(croppedCards.count)...")

            if let identified = await resolvePrinting(cardImage: cardImage, wasCropped: true) {
                let resolved = await resolveArtVariant(card: identified, cardImage: cardImage)
                results.append(resolved)
            }
        }

        return results
    }

    // MARK: - Step 1: OCR Signal Extraction

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
            return nil
        }
    }

    // MARK: - Step 2: Printing Resolution

    private func resolvePrinting(cardImage: CGImage, wasCropped: Bool) async -> Card? {
        guard let signals = await extractOCRSignals(from: cardImage, wasCropped: wasCropped) else {
            return nil
        }

        // Step 2a: Collector number + set code (most precise)
        if let match = await matchByCollectorNumber(signals: signals) {
            return match
        }

        // Step 2b-e: Metadata filtering + image comparison
        if let match = await matchByMetadata(signals: signals, cardImage: cardImage) {
            return match
        }

        // Step 2f: Fallback — try alternative names from rules text
        // Old-frame cards have stylized title fonts that OCR mangles,
        // but rules text uses a clean font and often contains the card's own name
        return await matchByAlternativeNames(signals: signals, cardImage: cardImage)
    }

    /// Tries to find the card name in the rules text when the title OCR was mangled.
    /// Cards often reference themselves by name (e.g., "Mishra's Factory becomes an...").
    private func matchByAlternativeNames(signals: OCRSignals, cardImage: CGImage) async -> Card? {
        // Collect potential card names from OCR text lines (skip the title, which already failed)
        for result in signals.scanResults {
            let text = result.recognizedText

            // Look for lines that might contain a card name referencing itself
            // Common patterns: "{Name} becomes", "{Name} deals", "Sacrifice {Name}"
            // We try each text segment that could be a card name
            let words = text.split(separator: " ")
            guard words.count >= 2 else { continue }

            // Try progressively longer substrings as potential card names
            for length in stride(from: min(words.count, 5), through: 2, by: -1) {
                for startIdx in 0...(words.count - length) {
                    let candidate = words[startIdx..<(startIdx + length)].joined(separator: " ")

                    // Skip very short candidates or the original failed name
                    guard candidate.count >= 5 else { continue }
                    guard candidate.lowercased() != signals.cardName.lowercased() else { continue }

                    // Try to find this name in the DB
                    if let printings = try? await repository.findAllPrintings(name: candidate),
                       !printings.isEmpty {
                        print("[MTGScanner] Found card via rules text: '\(candidate)' (\(printings.count) printings)")

                        // Re-run metadata matching with the corrected name
                        var correctedSignals = signals
                        correctedSignals = OCRSignals(
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

        return nil
    }

    /// Step 2a: Match by collector number (+ optional set code).
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

    /// Steps 2b-e: Metadata filtering, priority sort, image comparison.
    private func matchByMetadata(signals: OCRSignals, cardImage: CGImage) async -> Card? {
        guard var printings = try? await repository.findAllPrintings(name: signals.cardName),
              !printings.isEmpty else { return nil }

        print("[MTGScanner] All printings for '\(signals.cardName)': \(printings.count)")

        // Filter by artist
        if let artistName = signals.artistName {
            let la = artistName.lowercased()
            let filtered = printings.filter { card in
                guard let a = card.artist else { return false }
                let ca = a.lowercased()
                return ca.contains(la) || la.contains(ca)
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

        // Multiple candidates — compare full card images
        if printings.count > 1 {
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

    // MARK: - Step 3: Art Variant Resolution

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
}
