import Foundation
import CoreGraphics
import Observation
import UIKit

// MARK: - Deck Scan State

/// Represents the current state of the deck scanning flow.
enum DeckScanState: Equatable {
    case selectingPhoto
    case adjustingGrid
    case processing(current: Int, total: Int)
    case results

    static func == (lhs: DeckScanState, rhs: DeckScanState) -> Bool {
        switch (lhs, rhs) {
        case (.selectingPhoto, .selectingPhoto): return true
        case (.adjustingGrid, .adjustingGrid): return true
        case (.processing(let lc, let lt), .processing(let rc, let rt)):
            return lc == rc && lt == rt
        case (.results, .results): return true
        default: return false
        }
    }
}

// MARK: - Deck Scan View Model

/// Manages the deck photo scanning workflow: photo selection, grid adjustment,
/// cell-by-cell identification, and decklist generation.
@Observable
final class DeckScanViewModel {

    // MARK: - Properties

    var sourceImage: CGImage?
    var rows: Int = 3
    var columns: Int = 7
    var identifiedCards: [Card] = []
    var scanState: DeckScanState = .selectingPhoto
    var processingProgress: Double = 0

    private let pipeline: CardIdentificationPipelineProtocol
    private let cardDetector = CardDetector()
    private let textClusterDetector = TextClusterCardDetector()
    private let colorDetector = ColorSegmentationCardDetector()
    private let mlDetector = MLCardDetector()

    // MARK: - Initialization

    init(pipeline: CardIdentificationPipelineProtocol) {
        self.pipeline = pipeline
    }

    // MARK: - Actions

    /// Sets the source image and immediately starts card detection.
    /// Skips the grid-adjustment screen entirely — Vision's rectangle
    /// detector finds individual cards automatically. The grid size
    /// is only used as a fallback if zero rectangles are detected.
    func setImage(_ image: CGImage) {
        sourceImage = image
        autoDetectGrid(image: image) // still computed for fallback
        Task { await processGrid() }
    }

    /// Auto-detect the most likely grid layout based on image dimensions and MTG card aspect ratio.
    /// MTG cards are 63x88mm → aspect ratio 0.716 (width/height).
    /// Uses a combined score of aspect ratio error + cell count penalty to prefer simpler grids.
    /// Requires minimum 4 cells (a deck photo should have at least 4 cards).
    private func autoDetectGrid(image: CGImage) {
        let cardAspect = 0.716 // MTG card width/height
        let cellPenalty = 0.002 // Small penalty per cell — prefers simpler grids
        let minCellDimension = 200.0 // Minimum pixels per cell side

        var bestRows = 2
        var bestCols = 4
        var bestScore = Double.greatestFiniteMagnitude

        for r in 1...6 {
            for c in 1...10 {
                let cells = r * c
                guard cells >= 4 else { continue }

                let cellWidth = Double(image.width) / Double(c)
                let cellHeight = Double(image.height) / Double(r)

                // Skip if cells would be too small to contain a readable card
                guard cellWidth >= minCellDimension && cellHeight >= minCellDimension else { continue }

                let cellAspect = cellWidth / cellHeight
                let error = abs(cellAspect - cardAspect)

                // Combined score: aspect error + penalty for more cells
                let score = error + Double(cells) * cellPenalty

                if score < bestScore {
                    bestScore = score
                    bestRows = r
                    bestCols = c
                }
            }
        }

        rows = bestRows
        columns = bestCols
        let cellAspect = Double(image.width) / Double(columns) / (Double(image.height) / Double(rows))
        print("[MTGScanner] Auto-detected grid: \(rows) rows × \(columns) cols = \(rows * columns) cells (cell aspect: \(String(format: "%.3f", cellAspect)), target: 0.716)")
    }

    /// Crops each grid cell from the source image and identifies each card sequentially.
    @MainActor
    func processGrid() async {
        guard let image = sourceImage else { return }

        await pipeline.clearFeaturePrintCache()

        identifiedCards = []
        processingProgress = 0
        scanState = .processing(current: 0, total: 1)

        // === Gemini whole-image mode: skip detection entirely ===
        print("[DeckScan] Gemini active: \(GeminiVisionService.isActive) (configured: \(GeminiVisionService.isConfigured), enabled: \(GeminiVisionService.isEnabled), limit: \(GeminiVisionService.isDailyLimitReached))")
        if GeminiVisionService.isActive {
            print("[DeckScan] Sending whole image to Gemini...")
            scanState = .processing(current: 0, total: 1)
            let geminiResult = await pipeline.identifyAllWithGemini(image: image)
            print("[DeckScan] Gemini returned \(geminiResult.cards.count) cards\(geminiResult.analysis.map { " — \($0)" } ?? "")")
            if !geminiResult.cards.isEmpty {
                identifiedCards = geminiResult.cards.map(\.card)
                processingProgress = 1.0
                scanState = .results
                return
            }
            // Gemini failed — fall through to local pipeline
            print("[DeckScan] Gemini failed, falling back to local pipeline")
        }

        var cardImages: [CGImage] = []

        // ML model detection (most accurate if available)
        if mlDetector.isAvailable {
            let mlCrops = await mlDetector.detectAndCrop(in: image)
            if mlCrops.count >= 2 {
                cardImages = mlCrops
                print("[MTGScanner] ML model detected \(mlCrops.count) cards")
            }
        }

        // Only run classical detection if ML didn't find enough
        if cardImages.isEmpty {

        // Primary: COLOR SEGMENTATION. The playmat is a uniform color;
        // cards are NOT. Finding "non-playmat blobs" finds cards.
        // This is layout-independent — works for grids, triangles,
        // scattered cards, any arrangement. No text needed.
        let colorDetected = colorDetector.detectCards(in: image)

        if !colorDetected.isEmpty {
            // Use color segmentation results (even if only 1 card found).
            // Previously required ≥2 which caused 1-card results to be
            // discarded entirely. Augment with text clustering to catch
            // dark cards that color segmentation missed.
            var combined = colorDetected
            print("[MTGScanner] Color segmentation found \(colorDetected.count) cards")
            // Also run text clustering to find cards that color seg missed
            // (dark cards on dark playmats have low color distance)
            let textDetected = await textClusterDetector.detectCards(in: image)
            if !textDetected.isEmpty {
                // Add text-detected crops that don't overlap with color-detected ones
                for textCrop in textDetected {
                    let textRect = CGRect(x: 0, y: 0, width: textCrop.width, height: textCrop.height)
                    let overlaps = combined.contains { colorCrop in
                        // Simple overlap check: crops of similar size in similar position
                        abs(colorCrop.width - textCrop.width) < colorCrop.width / 2 &&
                        abs(colorCrop.height - textCrop.height) < colorCrop.height / 2
                    }
                    if !overlaps {
                        combined.append(textCrop)
                    }
                }
                if combined.count > colorDetected.count {
                    print("[MTGScanner] Text clustering added \(combined.count - colorDetected.count) more cards")
                }
            }
            // Also run edge detection to find dark cards on dark playmats
            let edgeDetected = await cardDetector.detectCardsViaEdges(in: image, maxCards: 20)
            if !edgeDetected.isEmpty {
                let beforeEdge = combined.count
                for edgeCrop in edgeDetected {
                    let overlaps = combined.contains { existing in
                        abs(existing.width - edgeCrop.width) < existing.width / 2 &&
                        abs(existing.height - edgeCrop.height) < existing.height / 2
                    }
                    if !overlaps {
                        combined.append(edgeCrop)
                    }
                }
                if combined.count > beforeEdge {
                    print("[MTGScanner] Edge detection added \(combined.count - beforeEdge) more cards")
                }
            }
            // Also run AI saliency detection
            let saliencyDetected = await cardDetector.detectCardsViaSaliency(in: image)
            if !saliencyDetected.isEmpty {
                let beforeSaliency = combined.count
                for crop in saliencyDetected {
                    let overlaps = combined.contains { existing in
                        abs(existing.width - crop.width) < existing.width / 2 &&
                        abs(existing.height - crop.height) < existing.height / 2
                    }
                    if !overlaps {
                        combined.append(crop)
                    }
                }
                if combined.count > beforeSaliency {
                    print("[MTGScanner] Saliency added \(combined.count - beforeSaliency) more cards")
                }
            }
            cardImages = combined
        } else {
            // Color segmentation found nothing — full fallback chain
            let textDetected = await textClusterDetector.detectCards(in: image)
            if !textDetected.isEmpty {
                cardImages = textDetected
                print("[MTGScanner] Text clustering found \(textDetected.count) cards")
            } else {
                let rectDetected = await cardDetector.detectAndCropAll(from: image, maxCards: 20)
                if !rectDetected.isEmpty {
                    cardImages = rectDetected
                    print("[MTGScanner] Rectangle detection found \(rectDetected.count) cards")
                } else {
                    // Try edge detection before falling back to grid
                    let edgeDetected = await cardDetector.detectCardsViaEdges(in: image, maxCards: 20)
                    if !edgeDetected.isEmpty {
                        cardImages = edgeDetected
                        print("[MTGScanner] Edge detection found \(edgeDetected.count) cards")
                    } else {
                        print("[MTGScanner] All detection failed, falling back to grid")
                        cardImages = extractGridCells(from: image)
                    }
                }
            }
        }

        } // end if cardImages.isEmpty

        let total = cardImages.count
        guard total > 0 else {
            scanState = .results
            return
        }

        // Identify cards in parallel for speed.
        scanState = .processing(current: 1, total: total)
        var completed = 0
        let maxConcurrency = min(3, total)
        await withTaskGroup(of: Card?.self) { group in
            var queued = 0
            for cropped in cardImages {
                if queued >= maxConcurrency {
                    if let card = await group.next() ?? nil {
                        identifiedCards.append(card)
                    }
                    completed += 1
                    scanState = .processing(current: completed + 1, total: total)
                    processingProgress = Double(completed) / Double(total)
                }
                group.addTask {
                    await self.pipeline.identifyCropped(cardImage: cropped, visualOnly: false)
                }
                queued += 1
            }
            for await card in group {
                if let card { identifiedCards.append(card) }
                completed += 1
                scanState = .processing(current: min(completed + 1, total), total: total)
                processingProgress = Double(completed) / Double(total)
            }
        }

        processingProgress = 1.0
        scanState = .results
    }

    /// Grid-based fallback: splits the image into `rows × columns`
    /// cells, filters by luminance variance, returns valid cells.
    private func extractGridCells(from image: CGImage) -> [CGImage] {
        let cellWidth = image.width / columns
        let cellHeight = image.height / rows
        let overlapV = cellHeight * 8 / 100
        var cells: [CGImage] = []
        for row in 0..<rows {
            for col in 0..<columns {
                let y = row * cellHeight
                let h = min(cellHeight + overlapV, image.height - y)
                let rect = CGRect(x: col * cellWidth, y: y, width: cellWidth, height: h)
                guard let cropped = image.cropping(to: rect) else { continue }
                if Self.isCellLikelyCard(cropped) {
                    cells.append(cropped)
                }
            }
        }
        return cells
    }

    // MARK: - Grid cell pre-validation

    /// Fast check (~5ms) to determine if a grid cell likely contains
    /// an MTG card vs. playmat background. Samples luminance at a
    /// grid of points and computes variance. Cards have high variance
    /// (mixed text, art, borders); solid playmats have near-zero.
    ///
    /// Also checks edge density via a simple horizontal-gradient
    /// approximation: cards have many sharp transitions (text edges,
    /// border lines), backgrounds are smooth.
    private static func isCellLikelyCard(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        guard width > 20 && height > 20 else { return false }

        // Create a small bitmap context to sample pixels efficiently.
        // Drawing the CGImage into an 8×8 thumbnail gives us 64
        // sample points in one fast blit — much cheaper than
        // accessing the full-resolution pixel buffer.
        let sampleSize = 8
        let bytesPerRow = sampleSize * 4
        var pixelData = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        guard let context = CGContext(
            data: &pixelData,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true } // On failure, assume card (safe fallback)

        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        // Compute luminance for each sample point.
        var luminances: [Double] = []
        for i in 0..<(sampleSize * sampleSize) {
            let offset = i * 4
            let r = Double(pixelData[offset])
            let g = Double(pixelData[offset + 1])
            let b = Double(pixelData[offset + 2])
            // Standard luminance weights (ITU-R BT.601)
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            luminances.append(lum)
        }

        // Variance: high for cards (~1000+), low for solid playmats (~50-200).
        let mean = luminances.reduce(0, +) / Double(luminances.count)
        let variance = luminances.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(luminances.count)

        // Tuned threshold: red playmats with logos have ~400-500
        // variance, while cards (even dark black-bordered ones) are
        // ≥800. Using 700 as the midpoint catches most playmat
        // backgrounds while preserving card detection.
        if variance < 700 {
            return false  // Very likely a solid-color background
        }

        // Edge density: count adjacent pixels with large luminance
        // difference (horizontal neighbors). Cards have many transitions;
        // backgrounds have few.
        var edgeCount = 0
        for row in 0..<sampleSize {
            for col in 0..<(sampleSize - 1) {
                let diff = abs(luminances[row * sampleSize + col] - luminances[row * sampleSize + col + 1])
                if diff > 30 { edgeCount += 1 }
            }
        }
        // At 8×7 possible edges, a card has ~15-40 edges, a playmat has ~0-5.
        if edgeCount < 5 {
            return false  // Too smooth — likely background
        }

        return true
    }

    /// Groups identified cards by name and returns sorted by quantity descending.
    func buildDecklist() -> [(name: String, card: Card, quantity: Int)] {
        var grouped: [String: (card: Card, count: Int)] = [:]

        for card in identifiedCards {
            if let existing = grouped[card.name] {
                grouped[card.name] = (card: existing.card, count: existing.count + 1)
            } else {
                grouped[card.name] = (card: card, count: 1)
            }
        }

        return grouped.values
            .map { (name: $0.card.name, card: $0.card, quantity: $0.count) }
            .sorted { $0.quantity > $1.quantity }
    }

    /// Resets to the initial photo selection state.
    func reset() {
        sourceImage = nil
        identifiedCards = []
        processingProgress = 0
        scanState = .selectingPhoto
    }

    // MARK: - Private Helpers

    /// Converts a CGImage to JPEG data for passing to the identification pipeline.
    private func cgImageToJPEGData(_ cgImage: CGImage) -> Data? {
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: 0.85)
    }
}
