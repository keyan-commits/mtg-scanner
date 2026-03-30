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

/// Manages the photo-picker-based card identification workflow.
/// Delegates all identification logic to `CardIdentificationPipeline`.
@Observable
final class CardScannerViewModel {

    // MARK: - Properties

    var scanState: ScanState = .idle
    var scannedCards: [Card] = []
    var processingProgress: Double = 0

    private let pipeline: CardIdentificationPipelineProtocol

    // MARK: - Initialization

    init(pipeline: CardIdentificationPipelineProtocol) {
        self.pipeline = pipeline
    }

    /// Convenience initializer that builds the pipeline from individual components.
    init(
        recognizer: TextRecognizerProtocol,
        nameExtractor: CardNameExtractor,
        repository: CardRepositoryProtocol
    ) {
        self.pipeline = CardIdentificationPipeline(
            recognizer: recognizer,
            repository: repository
        )
    }

    // MARK: - Actions

    /// Processes selected photos from the photo picker.
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

                if let card = await pipeline.identify(imageData: data) {
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
        } else {
            scanState = .completed(scannedCards)
        }
    }

    /// Processes raw image data through the identification pipeline.
    /// Exposed for testability.
    @MainActor
    func processImageData(_ data: Data) async -> Card? {
        await pipeline.identify(imageData: data)
    }

    /// Resets to idle state.
    func resetScan() {
        scanState = .idle
        scannedCards = []
        processingProgress = 0
    }
}
