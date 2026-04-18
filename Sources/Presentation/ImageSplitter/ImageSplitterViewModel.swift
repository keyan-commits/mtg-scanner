import Foundation
import CoreGraphics
import UIKit
import Photos
import Vision

/// Manages the image splitting workflow: detect cards, overlay prices, save to photos.
@Observable
@MainActor
final class ImageSplitterViewModel {

    // MARK: - State

    var sourceImage: CGImage?
    var detectedCards: [(image: CGImage, rect: CGRect)] = []
    var selectedIndices: Set<Int> = []
    var priceOverlayEnabled = true
    var manualPrices: [Int: String] = [:]
    var identifiedCards: [Int: Card] = [:]
    /// Quantity per card index (default 1, range 1–20). Used when adding to collection.
    var quantities: [Int: Int] = [:]
    /// Debug logs per card index for troubleshooting.
    var debugLogs: [Int: String] = [:]

    var isDetecting = false
    var isIdentifying = false
    var isSaving = false
    var identifyingProgress: (current: Int, total: Int)?
    var saveError: String?
    var saveSuccess = false
    var showSaveAlert = false
    var addedToCollection = false
    var showAddedAlert = false

    /// Stores the rect at the START of a drag, so cumulative translation works correctly.
    var dragStartRects: [Int: CGRect] = [:]

    private let colorDetector = ColorSegmentationCardDetector()
    private let rectDetector = CardDetector()
    private let textClusterDetector = TextClusterCardDetector()
    private let mlDetector = MLCardDetector()
    private let pipeline: CardIdentificationPipelineProtocol?
    let deckRepository: DeckListRepository?

    var trainingDataCount: Int { TrainingDataCollector.shared.trainingDataCount() }
    var embeddingCount: Int = 0
    var embeddingUniqueCards: Int = 0

    init(pipeline: CardIdentificationPipelineProtocol? = nil, deckRepository: DeckListRepository? = nil) {
        self.pipeline = pipeline
        self.deckRepository = deckRepository
    }

    // MARK: - Detection

    func setImage(_ image: CGImage) {
        sourceImage = image
        detectedCards = []
        selectedIndices = []
        identifiedCards = [:]
        quantities = [:]
        manualPrices = [:]
        saveSuccess = false
        addedToCollection = false
    }

    /// Runs all detection methods and merges results.
    func detect() async {
        guard let image = sourceImage else { return }
        isDetecting = true

        let imgArea = image.width * image.height

        // Strategy 0: ML model detection (most accurate if trained model exists)
        if mlDetector.isAvailable {
            var mlCards: [(image: CGImage, rect: CGRect)] = []
            let mlRects = await mlDetector.detectCards(in: image)
            for rect in mlRects {
                guard let cropped = image.cropping(to: rect.integral) else { continue }
                let cropArea = Double(cropped.width * cropped.height)
                guard cropArea / Double(imgArea) < 0.40 && cropArea / Double(imgArea) > 0.01 else { continue }
                mlCards.append((image: cropped, rect: rect))
            }
            if !mlCards.isEmpty {
                print("[ImageSplitter] ML model detected \(mlCards.count) cards")
                // ML model is authoritative — skip other strategies
                detectedCards = mlCards
                selectedIndices = Set(mlCards.indices)
                isDetecting = false
                return
            }
        }

        // Strategy 1: Color segmentation (with rects for bounding boxes)
        let colorResults = colorDetector.detectCardsWithRects(in: image)
        var allCards = colorResults
        print("[ImageSplitter] Color segmentation: \(colorResults.count) cards")

        // Strategy 2: Rectangle detection (Vision framework, tuned for cards)
        let rectCrops = await rectDetector.detectAndCropAll(from: image, maxCards: 20)
        for crop in rectCrops {
            // Reject crops that are too large (>35% of image = not a single card)
            let cropArea = crop.width * crop.height
            guard Double(cropArea) / Double(imgArea) < 0.35 else {
                print("[ImageSplitter] Rejected oversized rect crop: \(crop.width)x\(crop.height)")
                continue
            }
            // Reject crops that are too small (<1% of image)
            guard Double(cropArea) / Double(imgArea) > 0.01 else { continue }

            let cropRect = CGRect(x: 0, y: 0, width: crop.width, height: crop.height)
            let overlaps = allCards.contains { existing in
                abs(existing.image.width - crop.width) < existing.image.width / 3 &&
                abs(existing.image.height - crop.height) < existing.image.height / 3
            }
            if !overlaps {
                allCards.append((image: crop, rect: cropRect))
            }
        }
        print("[ImageSplitter] After rectangle detection: \(allCards.count) cards")

        // Strategy 2.5: Edge-based detection (Canny edges + rectangles)
        // Catches dark cards on dark playmats where color contrast is low
        let edgeCrops = await rectDetector.detectCardsViaEdges(in: image, maxCards: 20)
        for crop in edgeCrops {
            let cropArea = crop.width * crop.height
            guard Double(cropArea) / Double(imgArea) < 0.35 else { continue }
            guard Double(cropArea) / Double(imgArea) > 0.01 else { continue }

            let cropRect = CGRect(x: 0, y: 0, width: crop.width, height: crop.height)
            let overlaps = allCards.contains { existing in
                abs(existing.image.width - crop.width) < existing.image.width / 3 &&
                abs(existing.image.height - crop.height) < existing.image.height / 3
            }
            if !overlaps {
                allCards.append((image: crop, rect: cropRect))
            }
        }
        print("[ImageSplitter] After edge detection: \(allCards.count) cards")

        // Strategy 3: Text clustering
        let textCrops = await textClusterDetector.detectCards(in: image)
        for crop in textCrops {
            let cropArea = crop.width * crop.height
            guard Double(cropArea) / Double(imgArea) < 0.35 else { continue }
            guard Double(cropArea) / Double(imgArea) > 0.01 else { continue }

            let cropRect = CGRect(x: 0, y: 0, width: crop.width, height: crop.height)
            let overlaps = allCards.contains { existing in
                abs(existing.image.width - crop.width) < existing.image.width / 3 &&
                abs(existing.image.height - crop.height) < existing.image.height / 3
            }
            if !overlaps {
                allCards.append((image: crop, rect: cropRect))
            }
        }
        print("[ImageSplitter] After text clustering: \(allCards.count) cards")

        // Strategy 4: AI Saliency detection (neural network objectness)
        // Finds "interesting" regions by content, not edges or color
        let saliencyCrops = await rectDetector.detectCardsViaSaliency(in: image)
        for crop in saliencyCrops {
            let cropArea = crop.width * crop.height
            guard Double(cropArea) / Double(imgArea) < 0.35 else { continue }
            guard Double(cropArea) / Double(imgArea) > 0.01 else { continue }

            let cropRect = CGRect(x: 0, y: 0, width: crop.width, height: crop.height)
            let overlaps = allCards.contains { existing in
                abs(existing.image.width - crop.width) < existing.image.width / 3 &&
                abs(existing.image.height - crop.height) < existing.image.height / 3
            }
            if !overlaps {
                allCards.append((image: crop, rect: cropRect))
            }
        }
        print("[ImageSplitter] After saliency: \(allCards.count) cards")

        detectedCards = allCards
        selectedIndices = Set(allCards.indices)
        isDetecting = false
    }

    // MARK: - Manual Region

    func addManualRegion(at point: CGPoint) {
        guard let image = sourceImage else { return }
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        let cardW = imgW * 0.25
        let cardH = cardW / 0.716

        let x = max(0, min(point.x - cardW / 2, imgW - cardW))
        let y = max(0, min(point.y - cardH / 2, imgH - cardH))
        let rect = CGRect(x: x, y: y, width: cardW, height: cardH)

        guard let cropped = image.cropping(to: rect) else { return }
        let newIndex = detectedCards.count
        detectedCards.append((image: cropped, rect: rect))
        selectedIndices.insert(newIndex)
        return // caller should exit add mode after this
    }

    /// Captures the rect at drag start for correct cumulative translation.
    func beginDrag(at index: Int) {
        guard index < detectedCards.count else { return }
        dragStartRects[index] = detectedCards[index].rect
    }

    /// Updates a bounding box rect and re-crops the image.
    func updateRegion(at index: Int, newRect: CGRect) {
        guard let image = sourceImage, index < detectedCards.count else { return }
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)

        // Clamp to image bounds
        let clamped = CGRect(
            x: max(0, min(newRect.origin.x, imgW - 20)),
            y: max(0, min(newRect.origin.y, imgH - 20)),
            width: max(20, min(newRect.width, imgW - newRect.origin.x)),
            height: max(20, min(newRect.height, imgH - newRect.origin.y))
        )

        guard let cropped = image.cropping(to: clamped) else { return }
        detectedCards[index] = (image: cropped, rect: clamped)
        // Clear stale identification for this card
        identifiedCards.removeValue(forKey: index)
    }

    // MARK: - Quantity

    func setQuantity(_ qty: Int, for index: Int) {
        quantities[index] = max(1, min(qty, 20))

        // Save stack count training data
        guard index < detectedCards.count else { return }
        let cropImage = detectedCards[index].image
        StackCountTrainer.shared.saveTrainingData(image: cropImage, count: quantities[index] ?? 1)
    }

    /// Estimates stack count by running OCR on the crop and counting how many times
    /// the card name appears at distinct vertical positions (stacked cards show
    /// multiple title bars offset vertically).
    func estimateStackCount(cardImage: CGImage, cardName: String) async -> Int {
        // Crop the top 30% of the image where title bars are visible
        let topHeight = Int(Double(cardImage.height) * 0.30)
        guard topHeight > 10 else { return 1 }
        let topRect = CGRect(x: 0, y: 0, width: cardImage.width, height: topHeight)
        guard let topCrop = cardImage.cropping(to: topRect) else { return 1 }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: topCrop, options: [:])
        guard let _ = try? handler.perform([request]) else { return 1 }

        // Collect Y positions where we find text matching the card name
        let nameWords = cardName.lowercased().split(separator: " ").filter { $0.count >= 3 }
        guard !nameWords.isEmpty else { return 1 }

        var matchYPositions: [CGFloat] = []

        for observation in (request.results ?? []) {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.lowercased()

            // Check if any significant word from the card name appears in this text
            let matchesName = nameWords.contains { word in text.contains(word) }
            if matchesName {
                // Use the midY of the bounding box (in normalized coordinates)
                let midY = observation.boundingBox.midY
                // Check if this Y position is distinct from already found positions
                let isDistinct = matchYPositions.allSatisfy { abs($0 - midY) > 0.08 }
                if isDistinct {
                    matchYPositions.append(midY)
                }
            }
        }

        let count = max(1, matchYPositions.count)
        return min(count, 20)
    }

    // MARK: - Identification

    func identifyCards() async {
        guard let pipeline else { return }

        await pipeline.clearFeaturePrintCache()

        // Save training data for future ML model training
        if let image = sourceImage {
            let rects = selectedIndices.sorted().compactMap { index -> CGRect? in
                guard index < detectedCards.count else { return nil }
                return detectedCards[index].rect
            }
            TrainingDataCollector.shared.saveTrainingData(image: image, cardRects: rects)
        }

        isIdentifying = true
        identifiedCards = [:]
        debugLogs = [:]
        let indices = Array(selectedIndices).sorted()
        let total = indices.count
        var current = 0

        for index in indices {
            guard index < detectedCards.count else { continue }
            let cardImage = detectedCards[index].image
            let w = cardImage.width, h = cardImage.height
            var log = "Crop: \(w)x\(h)\n"

            // Debug: check CJK detection
            let cjkRequest = VNRecognizeTextRequest()
            cjkRequest.recognitionLevel = .fast
            cjkRequest.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            let cjkHandler = VNImageRequestHandler(cgImage: cardImage, options: [:])
            var hasCJK = false
            var cjkSample = ""
            if let _ = try? cjkHandler.perform([cjkRequest]) {
                for obs in (cjkRequest.results ?? []) {
                    if let text = obs.topCandidates(1).first?.string {
                        let isCJK = text.unicodeScalars.contains { s in (0x4E00...0x9FFF).contains(s.value) }
                        if isCJK { hasCJK = true; cjkSample = String(text.prefix(10)); break }
                    }
                }
            }
            log += "CJK: \(hasCJK)\(hasCJK ? " [\(cjkSample)]" : "")\n"

            var card: Card?

            // Strategy 0: Gemini Vision (most accurate for binder pages)
            if GeminiVisionService.isConfigured {
                log += "Trying Gemini Vision...\n"
                card = await pipeline.identifyWithGemini(cgImage: cardImage)
                if let card {
                    log += "Gemini: \(card.name) [\(card.set.code)]\n"
                } else {
                    log += "Gemini: nil, falling back to local...\n"
                }
            }

            // Strategy 1: Local OCR flow (works for high-quality single card photos)
            if card == nil {
                card = await pipeline.identify(cgImage: cardImage)
            }
            // Strategy 2: Visual search (works for binder pages, sleeves, low-res crops)
            if card == nil {
                log += "OCR flow: nil, trying visual search...\n"
                card = await pipeline.identifyCropped(cardImage: cardImage, visualOnly: false)
            }
            if let card {
                identifiedCards[index] = card
                log += "Result: \(card.name) [\(card.set.code)] #\(card.collectorNumber)"
            } else {
                log += "Result: NOT IDENTIFIED"
            }
            debugLogs[index] = log
            current += 1
            identifyingProgress = (current: current, total: total)
        }

        // Cross-match: compare unidentified cards against identified ones.
        // Only matches cards that are TRULY the same (e.g., foreign language version).
        // OCR cross-validation prevents mismatches (e.g., "Swamp" labeled as "Bayou"
        // because old-frame cards look similar via VNFeaturePrint).
        let unidentifiedIndices = indices.filter { identifiedCards[$0] == nil }
        if !unidentifiedIndices.isEmpty && !identifiedCards.isEmpty {
            let matcher = ImageMatcher()
            for unidIndex in unidentifiedIndices {
                guard unidIndex < detectedCards.count else { continue }
                let unidImage = detectedCards[unidIndex].image

                // Quick OCR check: try to read the card name from the unidentified crop
                let ocrName = await quickOCRCardName(from: unidImage)

                var bestMatch: Card?
                var bestDist: Float = .greatestFiniteMagnitude

                for (idIndex, card) in identifiedCards {
                    guard idIndex < detectedCards.count else { continue }

                    // If OCR read a name and it doesn't match the candidate, skip
                    if let name = ocrName, !name.isEmpty {
                        let ocrLower = name.lowercased()
                        let cardLower = card.name.lowercased()
                        if !cardLower.contains(ocrLower) && !ocrLower.contains(cardLower) {
                            continue
                        }
                    }

                    let idImage = detectedCards[idIndex].image
                    guard let dist = await matcher.distance(between: unidImage, and: idImage) else { continue }
                    if dist < bestDist {
                        bestDist = dist
                        bestMatch = card
                    }
                }

                // Threshold 5.0: very strict. Only truly identical cards match.
                // Old-frame cards from the same set can score 6-10 despite being
                // completely different cards (same frame, border, layout).
                if let match = bestMatch, bestDist < 5.0 {
                    identifiedCards[unidIndex] = match
                    debugLogs[unidIndex] = (debugLogs[unidIndex] ?? "") + "\nCross-match: \(match.name) (dist: \(String(format: "%.1f", bestDist)))"
                    print("[ImageSplitter] Cross-matched unidentified card \(unidIndex) → \(match.name) (dist: \(bestDist))")
                }
            }
        }

        // Estimate stack counts for identified cards (auto-detect quantity)
        quantities = [:]
        for (index, card) in identifiedCards {
            guard index < detectedCards.count else { continue }
            let cardImage = detectedCards[index].image
            let stackCount = await estimateStackCount(cardImage: cardImage, cardName: card.name)
            if stackCount > 1 {
                quantities[index] = stackCount
                print("[ImageSplitter] Stack detected for \(card.name): \(stackCount) copies")
            }
        }

        isIdentifying = false
        identifyingProgress = nil
    }

    // MARK: - Quick OCR

    /// Fast OCR pass to read the card name from a crop image.
    /// Used by cross-match to prevent mismatches (e.g., "Swamp" → "Bayou").
    private func quickOCRCardName(from image: CGImage) async -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }

        // The card name is typically the TOPMOST text line
        guard let results = request.results, !results.isEmpty else { return nil }

        // Sort by Y position (Vision coords: y=0 bottom, y=1 top) — highest Y = topmost
        let sorted = results.compactMap { obs -> (String, CGFloat)? in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return (text, obs.boundingBox.maxY)
        }.sorted { $0.1 > $1.1 }

        // Return the topmost text that looks like a card name (2+ chars, not just numbers)
        for (text, _) in sorted {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2 && trimmed.contains(where: \.isLetter) {
                return trimmed
            }
        }
        return nil
    }

    // MARK: - Price

    func priceString(for index: Int) -> String? {
        if let manual = manualPrices[index], !manual.isEmpty {
            return manual
        }
        if let card = identifiedCards[index], let usd = card.prices.usd {
            return "$\(usd)"
        }
        return nil
    }

    // MARK: - Correction

    /// Message shown after a correction is applied.
    var correctionFeedback: String?

    /// Applies a user correction: replaces the identified card and feeds the
    /// correction into the FeaturePrint cache so future scans improve.
    func correctCard(at index: Int, to card: Card, correctionService: CardCorrectionService?) {
        let oldName = identifiedCards[index]?.name ?? "Unknown"
        identifiedCards[index] = card

        var learnings: [String] = []

        // Feed correction to FeaturePrint cache + embedding store — ML learns from this
        if let service = correctionService,
           index < detectedCards.count {
            let cropImage = detectedCards[index].image
            Task {
                await service.applyCorrection(correctCard: card, originalCardImage: cropImage)
                if let store = service.embeddingStore {
                    await MainActor.run { self.embeddingCount = 0; self.embeddingUniqueCards = 0 }
                    let count = await store.count
                    let unique = await store.uniqueCardCount
                    await MainActor.run { self.embeddingCount = count; self.embeddingUniqueCards = unique }
                }
            }
            learnings.append("FP cache updated")
            learnings.append("embedding stored")
        }

        // Also save training data so the detection model benefits
        if let image = sourceImage {
            let rects = selectedIndices.sorted().compactMap { i -> CGRect? in
                guard i < detectedCards.count else { return nil }
                return detectedCards[i].rect
            }
            TrainingDataCollector.shared.saveTrainingData(image: image, cardRects: rects)
            learnings.append("training sample #\(trainingDataCount) saved")
        }

        let learnStr = learnings.isEmpty ? "" : " (\(learnings.joined(separator: ", ")))"
        correctionFeedback = "\(oldName) → \(card.name) [\(card.set.code)]\(learnStr)"

        // Auto-dismiss after 3 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if correctionFeedback?.contains(card.name) == true {
                correctionFeedback = nil
            }
        }
    }

    // MARK: - Add to Collection

    /// Total quantity of all identified cards (respecting per-card quantities).
    var totalCardQuantity: Int {
        selectedIndices.reduce(0) { sum, index in
            guard identifiedCards[index] != nil else { return sum }
            return sum + (quantities[index] ?? 1)
        }
    }

    func addToCollection() {
        guard let repo = deckRepository else { return }
        var added = 0
        for index in selectedIndices.sorted() {
            if let card = identifiedCards[index] {
                let qty = quantities[index] ?? 1
                try? repo.addToCollection(card: card, quantity: qty)
                added += qty
            }
        }
        if added > 0 {
            addedToCollection = true
            showAddedAlert = true
        }
    }

    // MARK: - Save to Photos

    func saveSelectedCards() async {
        isSaving = true
        saveError = nil
        saveSuccess = false

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveError = "Photo library access denied. Go to Settings to enable."
            isSaving = false
            return
        }

        var imagesToSave: [UIImage] = []
        for index in selectedIndices.sorted() {
            guard index < detectedCards.count else { continue }
            var cardImage = detectedCards[index].image

            if priceOverlayEnabled, let price = priceString(for: index) {
                cardImage = overlayPriceLabel(on: cardImage, price: price)
            }

            imagesToSave.append(UIImage(cgImage: cardImage))
        }

        guard !imagesToSave.isEmpty else {
            saveError = "No cards selected"
            isSaving = false
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for uiImage in imagesToSave {
                    PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
                }
            }
            saveSuccess = true
            showSaveAlert = true
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    // MARK: - Price Overlay

    private func overlayPriceLabel(on cgImage: CGImage, price: String) -> CGImage {
        let uiImage = UIImage(cgImage: cgImage)
        let size = uiImage.size

        let renderer = UIGraphicsImageRenderer(size: size)
        let result = renderer.image { _ in
            uiImage.draw(at: .zero)

            let font = UIFont.systemFont(ofSize: max(size.width * 0.07, 14), weight: .bold)
            let text = price as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            let padding: CGFloat = size.width * 0.025
            let badgeSize = CGSize(
                width: textSize.width + padding * 2,
                height: textSize.height + padding * 2
            )

            let badgeOrigin = CGPoint(
                x: size.width - badgeSize.width - padding * 2,
                y: size.height - badgeSize.height - padding * 2
            )
            let badgeRect = CGRect(origin: badgeOrigin, size: badgeSize)

            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeSize.height * 0.3)
            UIColor.black.withAlphaComponent(0.75).setFill()
            badgePath.fill()

            let textOrigin = CGPoint(
                x: badgeOrigin.x + padding,
                y: badgeOrigin.y + padding
            )
            text.draw(at: textOrigin, withAttributes: attributes)
        }

        return result.cgImage ?? cgImage
    }
}
