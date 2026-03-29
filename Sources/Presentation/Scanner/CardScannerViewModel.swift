import Foundation
import CoreGraphics
import Observation
import SwiftUI
import PhotosUI

// MARK: - Scan State

/// Represents the current state of the card scanning flow.
enum ScanState: Sendable {
    case idle
    case processing(current: Int, total: Int)
    case completed([Card])
    case error(String)
}

extension ScanState: Equatable {
    static func == (lhs: ScanState, rhs: ScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.processing(let lhsCurrent, let lhsTotal), .processing(let rhsCurrent, let rhsTotal)):
            return lhsCurrent == rhsCurrent && lhsTotal == rhsTotal
        case (.completed(let lhsCards), .completed(let rhsCards)):
            return lhsCards.count == rhsCards.count
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

// MARK: - Card Scanner View Model

/// Manages the photo-picker-based card scanning workflow: loading photos,
/// running OCR, extracting card names, and looking up cards in the repository.
@Observable
final class CardScannerViewModel {

    // MARK: - Properties

    /// The current state of the scanning workflow.
    var scanState: ScanState = .idle

    /// All successfully scanned cards from the current batch.
    var scannedCards: [Card] = []

    /// Processing progress from 0.0 to 1.0.
    var processingProgress: Double = 0

    private let recognizer: TextRecognizerProtocol
    private let nameExtractor: CardNameExtractor
    private let collectorInfoExtractor: CollectorInfoExtractor
    private let artistExtractor: ArtistExtractor
    private let copyrightYearExtractor: CopyrightYearExtractor
    private let borderColorDetector: BorderColorDetector
    private let imageMatcher: ImageMatcher
    private let setSymbolMatcher: SetSymbolMatcher
    private let cardDetector: CardDetector
    private let artVariantMatcher: ArtVariantMatcher
    private let repository: CardRepositoryProtocol
    private let imageProcessor: ImageProcessor

    // MARK: - Initialization

    init(
        recognizer: TextRecognizerProtocol,
        nameExtractor: CardNameExtractor,
        collectorInfoExtractor: CollectorInfoExtractor = CollectorInfoExtractor(),
        artistExtractor: ArtistExtractor = ArtistExtractor(),
        copyrightYearExtractor: CopyrightYearExtractor = CopyrightYearExtractor(),
        borderColorDetector: BorderColorDetector = BorderColorDetector(),
        imageMatcher: ImageMatcher = ImageMatcher(),
        setSymbolMatcher: SetSymbolMatcher = SetSymbolMatcher(),
        cardDetector: CardDetector = CardDetector(),
        artVariantMatcher: ArtVariantMatcher = ArtVariantMatcher(),
        repository: CardRepositoryProtocol,
        imageProcessor: ImageProcessor = ImageProcessor()
    ) {
        self.recognizer = recognizer
        self.nameExtractor = nameExtractor
        self.collectorInfoExtractor = collectorInfoExtractor
        self.artistExtractor = artistExtractor
        self.copyrightYearExtractor = copyrightYearExtractor
        self.borderColorDetector = borderColorDetector
        self.imageMatcher = imageMatcher
        self.setSymbolMatcher = setSymbolMatcher
        self.cardDetector = cardDetector
        self.artVariantMatcher = artVariantMatcher
        self.repository = repository
        self.imageProcessor = imageProcessor
    }

    // MARK: - Actions

    /// Processes selected photos from the photo picker.
    ///
    /// Loads each photo's data, downsamples it, runs OCR, extracts the card name,
    /// and looks up the card in the repository. Cards that fail to process are
    /// skipped gracefully. Updates `scanState` and `processingProgress` throughout.
    ///
    /// - Parameter items: The selected `PhotosPickerItem` instances.
    @MainActor
    func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            scanState = .completed([])
            return
        }

        scannedCards = []
        processingProgress = 0
        var failedCount = 0

        for (index, item) in items.enumerated() {
            scanState = .processing(current: index + 1, total: items.count)
            processingProgress = Double(index) / Double(items.count)

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failedCount += 1
                    continue
                }

                if let card = await processImageData(data) {
                    scannedCards.append(card)
                } else {
                    failedCount += 1
                }
            } catch {
                failedCount += 1
            }
        }

        processingProgress = 1.0

        if scannedCards.isEmpty && failedCount > 0 {
            scanState = .error(
                "Could not identify any cards from \(failedCount) photo(s). " +
                "Try clearer photos with the card name visible."
            )
        } else if failedCount > 0 {
            // Some succeeded, some failed — report as completed with a note
            scanState = .completed(scannedCards)
        } else {
            scanState = .completed(scannedCards)
        }
    }

    /// Processes raw image data through the OCR and card identification pipeline.
    ///
    /// This method is exposed for testability since `PhotosPickerItem` cannot
    /// be easily mocked.
    ///
    /// - Parameter data: Raw image data (JPEG, PNG, HEIC, etc.).
    /// - Returns: The identified `Card`, or `nil` if processing failed.
    @MainActor
    func processImageData(_ data: Data) async -> Card? {
        guard let rawImage = imageProcessor.downsample(data: data) else {
            return nil
        }

        // Identify the card, then resolve art variants
        let croppedCard = await cardDetector.detectAndCrop(from: rawImage)
        let cardImage = croppedCard ?? rawImage

        print("[MTGScanner] Card detection: \(croppedCard != nil ? "✓ cropped" : "✗ using raw image")")

        guard let identified = await identifyCard(cardImage: cardImage, wasCropped: croppedCard != nil) else {
            return nil
        }

        // Check for art variants within the same set
        return await resolveArtVariant(card: identified, cardImage: cardImage)
    }

    /// Core identification pipeline — returns the best card match before art variant resolution.
    @MainActor
    private func identifyCard(cardImage: CGImage, wasCropped: Bool) async -> Card? {
        print("[MTGScanner] Starting identification pipeline")

        do {
            let scanResults = try await recognizer.recognizeText(in: cardImage)

            for result in scanResults {
                print("[MTGScanner] OCR: '\(result.recognizedText)' conf=\(String(format: "%.2f", result.confidence)) y=\(String(format: "%.3f", result.boundingBox.origin.y))")
            }

            guard let cardName = nameExtractor.extractCardName(from: scanResults) else {
                return nil
            }

            // Extract all signals from OCR
            let collectorCandidates = collectorInfoExtractor.extractAllCandidates(from: scanResults)
            let artistName = artistExtractor.extractArtist(from: scanResults)
            let copyrightYear = copyrightYearExtractor.extractCopyrightEndYear(from: scanResults)
            let hasOldTypeLine = scanResults.contains { $0.recognizedText.lowercased().hasPrefix("summon") }

            // Border detection on CROPPED card image (reliable after crop, unreliable on raw photo)
            let detectedBorder = wasCropped ? borderColorDetector.detectBorderColor(in: cardImage) : nil

            print("[MTGScanner] Name: '\(cardName)' | Collector: \(collectorCandidates) | Artist: \(artistName ?? "nil") | Year: \(copyrightYear.map(String.init) ?? "nil") | Border: \(detectedBorder?.rawValue ?? "nil") | OldFrame: \(hasOldTypeLine)")

            // Step 1: Collector number + set code (most precise)
            if !collectorCandidates.isEmpty {
                let printings = try? await repository.findAllPrintings(name: cardName)
                if let printings, !printings.isEmpty {
                    for candidate in collectorCandidates {
                        guard let setCode = candidate.setCode, !candidate.collectorNumber.isEmpty else { continue }
                        let lowerCode = setCode.lowercased()
                        let num = candidate.collectorNumber
                        let match = printings.first { (c: Card) in c.set.code == lowerCode && c.collectorNumber == num }
                        if let match {
                            print("[MTGScanner] ✓ Matched by set+number: \(match.set.name) #\(match.collectorNumber)")
                            return match
                        }
                    }
                    for candidate in collectorCandidates {
                        guard !candidate.collectorNumber.isEmpty else { continue }
                        let num = candidate.collectorNumber
                        let match = printings.first { $0.collectorNumber == num }
                        if let match {
                            print("[MTGScanner] ✓ Matched by number: \(match.set.name) #\(match.collectorNumber)")
                            return match
                        }
                    }
                }
            }

            // Step 2: Metadata filtering (artist, year, frame, border)
            var printings = try await repository.findAllPrintings(name: cardName)
            print("[MTGScanner] All printings for '\(cardName)': \(printings.count)")

            if let artistName {
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

            if let year = copyrightYear {
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

            if hasOldTypeLine {
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

            // Border color filter — only used when card was successfully cropped (reliable)
            if let border = detectedBorder {
                let filtered = printings.filter { $0.borderColor == border.rawValue }
                if !filtered.isEmpty {
                    printings = filtered
                    print("[MTGScanner] After border filter (\(border.rawValue)): \(printings.count)")
                }
            }

            // Sort by preference: expansions > core > others > foreign/promos
            printings.sort { a, b in printingPriority(a) < printingPriority(b) }

            if printings.count == 1, let match = printings.first {
                print("[MTGScanner] ✓ Matched by metadata (unique): \(match.set.name) #\(match.collectorNumber)")
                return match
            }

            // Step 3: Multiple candidates — compare full card images
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

            // Step 4: Fallback to name-only lookup
            if let match = printings.first {
                return match
            }
            print("[MTGScanner] Falling back to name-only lookup")
            return try await repository.identifyCard(name: cardName)
        } catch {
            return nil
        }
    }

    /// Compares the set symbol region from the user's photo against candidate reference images.
    private func resolveBySymbolComparison(source: CGImage, scanResults: [ScanResult], candidates: [Card]) async -> Card? {
        // Download reference images for candidates
        var candidateImages: [(index: Int, image: CGImage)] = []
        for (index, card) in candidates.enumerated() {
            guard let urlString = card.imageURIs["normal"] ?? card.imageURIs["small"] else { continue }
            if let image = await imageMatcher.downloadImage(from: urlString) {
                candidateImages.append((index, image))
            }
        }
        guard !candidateImages.isEmpty else { return nil }

        // Try symbol-based matching
        if let bestIdx = await setSymbolMatcher.matchBySymbol(
            sourceImage: source,
            candidateImages: candidateImages.map { ($0.index, $0.image) },
            scanResults: scanResults
        ) {
            return candidates[bestIdx]
        }

        return nil
    }

    /// Downloads reference images for candidates and uses VNFeaturePrint to find the best match.
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

    /// Returns a priority score for a card's printing (lower = preferred).
    /// Regular expansions/core sets preferred over foreign variants and promos.
    private func printingPriority(_ card: Card) -> Int {
        let setName = card.set.name.lowercased()

        // Foreign/variant sets are always deprioritized
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

    /// Resets the scanner to its idle state, clearing all scanned cards and progress.
    /// Checks if the identified card has art variants in the same set,
    /// and resolves to the correct variant by comparing art regions.
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

    func resetScan() {
        scanState = .idle
        scannedCards = []
        processingProgress = 0
    }
}
