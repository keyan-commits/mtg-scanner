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

    // MARK: - Initialization

    init(pipeline: CardIdentificationPipelineProtocol) {
        self.pipeline = pipeline
    }

    // MARK: - Actions

    /// Sets the source image and transitions to the grid adjustment state.
    func setImage(_ image: CGImage) {
        sourceImage = image
        scanState = .adjustingGrid
    }

    /// Crops each grid cell from the source image and identifies each card sequentially.
    @MainActor
    func processGrid() async {
        guard let image = sourceImage else { return }

        let total = rows * columns
        identifiedCards = []
        processingProgress = 0
        scanState = .processing(current: 1, total: total)

        let cellWidth = image.width / columns
        let cellHeight = image.height / rows

        for row in 0..<rows {
            for col in 0..<columns {
                let index = row * columns + col
                scanState = .processing(current: index + 1, total: total)
                processingProgress = Double(index) / Double(total)

                let rect = CGRect(
                    x: col * cellWidth,
                    y: row * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )

                guard let cropped = image.cropping(to: rect) else { continue }

                if let card = await pipeline.identifyCropped(cardImage: cropped) {
                    identifiedCards.append(card)
                }
            }
        }

        processingProgress = 1.0
        scanState = .results
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
