import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

// MARK: - Helpers

private func makeTinyCGImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}

private func makeBatchCard(name: String, set: String = "lea", collector: String = "1") -> Card {
    Card(
        scryfallID: "\(name)-\(set)-\(collector)",
        name: name,
        manaCost: nil,
        typeLine: "Instant",
        oracleText: nil,
        set: SetInfo(code: set, name: set.uppercased(), setType: "expansion", iconSVGURI: nil, releasedAt: nil),
        collectorNumber: collector,
        rarity: .common,
        artist: nil,
        releasedAt: nil,
        borderColor: nil,
        frame: nil,
        frameEffects: [],
        illustrationID: nil,
        edhrecRank: nil,
        prices: CardPrices(usd: nil, usdFoil: nil, eur: nil, eurFoil: nil, tix: nil, previousUsd: nil),
        legalities: FormatLegality([:]),
        imageURIs: [:],
        relatedPrintingsURI: nil,
        lang: "en",
        printedName: nil,
        promoTypes: [],
        finishes: ["nonfoil"]
    )
}

/// Minimal pipeline stub — only `identifyBatch` is exercised by these tests.
private struct BatchStubPipeline: CardIdentificationPipelineProtocol {
    var batchResult: BatchIdentificationResult = BatchIdentificationResult(cards: [], payloadBytes: 0, error: nil)

    func identify(imageData: Data) async -> Card? { nil }
    func identify(cgImage: CGImage) async -> Card? { nil }
    func identifyCropped(cardImage: CGImage, visualOnly: Bool) async -> Card? { nil }
    func identifyAll(imageData: Data) async -> [Card] { [] }
    func identifyWithGemini(cgImage: CGImage) async -> Card? { nil }
    func identifyAllWithGemini(image: CGImage) async -> (analysis: String?, cards: [(card: Card, bbox: CGRect?)]) {
        (nil, [])
    }
    func learnFromIdentification(cardImage: CGImage, card: Card) async {}
    func identifyBatch(images: [CGImage]) async -> BatchIdentificationResult { batchResult }
    func clearFeaturePrintCache() async {}
}

// MARK: - Tests

@Suite("BatchScanViewModel Tests")
@MainActor
struct BatchScanViewModelTests {

    @Test("Pipeline error transitions viewmodel to .error state, not silent zero-of-N")
    func pipelineErrorSurfacesAsErrorState() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(), makeTinyCGImage(), makeTinyCGImage()]

        let result = BatchIdentificationResult(cards: [], payloadBytes: 0, error: "Rate limited — try again in a minute")
        viewModel.applyBatchResult(result)

        #expect(viewModel.state == .error("Rate limited — try again in a minute"))
        #expect(viewModel.identifiedCards.isEmpty)
        #expect(viewModel.failedIndices.isEmpty)
    }

    @Test("Successful empty result transitions to .results with all photos failed")
    func emptyButSuccessfulResult() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(), makeTinyCGImage()]

        let result = BatchIdentificationResult(cards: [], payloadBytes: 1234, error: nil)
        viewModel.applyBatchResult(result)

        #expect(viewModel.state == .results)
        #expect(viewModel.cardCount == 0)
        #expect(viewModel.payloadBytes == 1234)
        #expect(viewModel.failedIndices == [0, 1])
    }

    @Test("Multiple cards from same photo all share imageIndex; cardCount is sum")
    func multipleCardsFromOnePhoto() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(), makeTinyCGImage()]

        let bolt = makeBatchCard(name: "Lightning Bolt")
        let counter = makeBatchCard(name: "Counterspell")
        let prospector = makeBatchCard(name: "Skirk Prospector", set: "ons", collector: "230")

        let result = BatchIdentificationResult(
            cards: [
                (imageIndex: 0, card: bolt),
                (imageIndex: 0, card: counter),
                (imageIndex: 1, card: prospector),
            ],
            payloadBytes: 5000,
            error: nil
        )
        viewModel.applyBatchResult(result)

        #expect(viewModel.state == .results)
        #expect(viewModel.cardCount == 3)
        #expect(viewModel.photosWithCards == 2)
        #expect(viewModel.failedIndices.isEmpty)
    }

    @Test("Photos with no cards land in failedIndices")
    func partialFailureMarksFailedPhotos() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(), makeTinyCGImage(), makeTinyCGImage(), makeTinyCGImage()]

        let bolt = makeBatchCard(name: "Lightning Bolt")
        let result = BatchIdentificationResult(
            cards: [(imageIndex: 2, card: bolt)],
            payloadBytes: 1000,
            error: nil
        )
        viewModel.applyBatchResult(result)

        #expect(viewModel.cardCount == 1)
        #expect(viewModel.photosWithCards == 1)
        #expect(viewModel.failedIndices == [0, 1, 3])
    }

    @Test("Quantity-expanded duplicates count as separate detections")
    func quantityExpandedDuplicates() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]

        // Pipeline expands quantity=4 into 4 separate entries before this VM sees them.
        let prospector = makeBatchCard(name: "Skirk Prospector", set: "ons", collector: "230")
        let result = BatchIdentificationResult(
            cards: Array(repeating: (imageIndex: 0, card: prospector), count: 4),
            payloadBytes: 800,
            error: nil
        )
        viewModel.applyBatchResult(result)

        #expect(viewModel.cardCount == 4)
        #expect(viewModel.photosWithCards == 1)
        #expect(viewModel.failedIndices.isEmpty)
    }

    @Test("Reset clears all batch state back to selecting")
    func resetReturnsToSelecting() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        let bolt = makeBatchCard(name: "Lightning Bolt")
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [(imageIndex: 0, card: bolt)],
            payloadBytes: 500,
            error: nil
        ))
        viewModel.payloadBytes = 500

        viewModel.reset()

        #expect(viewModel.state == .selecting)
        #expect(viewModel.identifiedCards.isEmpty)
        #expect(viewModel.failedIndices.isEmpty)
        #expect(viewModel.payloadBytes == 0)
        #expect(viewModel.loadedImages.isEmpty)
    }
}
