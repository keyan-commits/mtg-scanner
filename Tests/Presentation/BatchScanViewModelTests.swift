import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

// MARK: - Helpers

private func makeTinyCGImage(side: Int = 200) -> CGImage {
    let context = CGContext(
        data: nil, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()!
}

private func makeBatchCard(
    name: String,
    set: String = "lea",
    collector: String = "1",
    usd: String? = nil,
    usdFoil: String? = nil,
    finishes: [String] = ["nonfoil"]
) -> Card {
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
        prices: CardPrices(usd: usd, usdFoil: usdFoil, eur: nil, eurFoil: nil, tix: nil, previousUsd: nil),
        legalities: FormatLegality([:]),
        imageURIs: [:],
        relatedPrintingsURI: nil,
        lang: "en",
        printedName: nil,
        promoTypes: [],
        finishes: finishes
    )
}

private func makeIdentified(
    imageIndex: Int,
    name: String,
    bbox: BatchBoundingBox? = nil,
    usd: String? = nil,
    usdFoil: String? = nil,
    finishes: [String] = ["nonfoil"]
) -> BatchIdentifiedCard {
    BatchIdentifiedCard(
        imageIndex: imageIndex,
        card: makeBatchCard(name: name, usd: usd, usdFoil: usdFoil, finishes: finishes),
        boundingBox: bbox
    )
}

/// Minimal pipeline stub — only `identifyBatch` and `learnFromIdentification`
/// are exercised by these tests.
private final class BatchStubPipeline: CardIdentificationPipelineProtocol, @unchecked Sendable {
    var batchResult: BatchIdentificationResult = BatchIdentificationResult(cards: [], payloadBytes: 0, analysis: nil, error: nil)
    /// Records every learnFromIdentification call. Tests assert against this.
    var learnedCardNames: [String] = []

    func identify(imageData: Data) async -> Card? { nil }
    func identify(cgImage: CGImage) async -> Card? { nil }
    func identifyCropped(cardImage: CGImage, visualOnly: Bool) async -> Card? { nil }
    func identifyAll(imageData: Data) async -> [Card] { [] }
    func identifyWithGemini(cgImage: CGImage) async -> Card? { nil }
    func identifyAllWithGemini(image: CGImage) async -> (analysis: String?, cards: [(card: Card, bbox: CGRect?)]) {
        (nil, [])
    }
    func learnFromIdentification(cardImage: CGImage, card: Card) async {
        learnedCardNames.append(card.name)
    }
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

        let result = BatchIdentificationResult(cards: [], payloadBytes: 0, analysis: nil, error: "Rate limited — try again in a minute")
        viewModel.applyBatchResult(result)

        #expect(viewModel.state == .error("Rate limited — try again in a minute"))
        #expect(viewModel.identifiedCards.isEmpty)
        #expect(viewModel.failedIndices.isEmpty)
    }

    @Test("Successful empty result transitions to .results with all photos failed")
    func emptyButSuccessfulResult() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(), makeTinyCGImage()]

        let result = BatchIdentificationResult(cards: [], payloadBytes: 1234, analysis: nil, error: nil)
        viewModel.applyBatchResult(result)

        #expect(viewModel.state == .results)
        #expect(viewModel.cardCount == 0)
        #expect(viewModel.payloadBytes == 1234)
        #expect(viewModel.failedIndices == [0, 1])
    }

    @Test("Multiple cards from same photo all share imageIndex; cardCount sums steppers")
    func multipleCardsFromOnePhoto() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(), makeTinyCGImage()]

        let result = BatchIdentificationResult(
            cards: [
                makeIdentified(imageIndex: 0, name: "Lightning Bolt"),
                makeIdentified(imageIndex: 0, name: "Counterspell"),
                makeIdentified(imageIndex: 1, name: "Skirk Prospector"),
            ],
            payloadBytes: 5000,
            analysis: nil,
            error: nil
        )
        viewModel.applyBatchResult(result)

        #expect(viewModel.state == .results)
        #expect(viewModel.cardCount == 3)
        #expect(viewModel.detectionCount == 3)
        #expect(viewModel.photosWithCards == 2)
        #expect(viewModel.failedIndices.isEmpty)
    }

    @Test("Quantity defaults to 1; stepper changes affect cardCount")
    func quantityStepper() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "Bolt"), makeIdentified(imageIndex: 0, name: "Counter")],
            payloadBytes: 100, analysis: nil, error: nil
        ))

        #expect(viewModel.quantity(at: 0) == 1)
        #expect(viewModel.cardCount == 2)

        viewModel.incrementQuantity(at: 0)
        viewModel.incrementQuantity(at: 0)
        #expect(viewModel.quantity(at: 0) == 3)
        #expect(viewModel.cardCount == 4)

        viewModel.decrementQuantity(at: 0)
        #expect(viewModel.quantity(at: 0) == 2)
    }

    @Test("Stepper clamps between 1 and 20")
    func stepperClamps() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "X")],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        viewModel.decrementQuantity(at: 0)
        viewModel.decrementQuantity(at: 0)
        #expect(viewModel.quantity(at: 0) == 1)
        viewModel.setQuantity(at: 0, to: 50)
        #expect(viewModel.quantity(at: 0) == 20)
    }

    @Test("Analysis string surfaces through viewmodel")
    func analysisSurfaces() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "X")],
            payloadBytes: 0, analysis: "Fancy goblin tribal", error: nil
        ))
        #expect(viewModel.analysis == "Fancy goblin tribal")
    }

    @Test("Photos with no cards land in failedIndices")
    func partialFailureMarksFailedPhotos() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(), makeTinyCGImage(), makeTinyCGImage(), makeTinyCGImage()]

        let result = BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 2, name: "X")],
            payloadBytes: 1000, analysis: nil, error: nil
        )
        viewModel.applyBatchResult(result)

        #expect(viewModel.cardCount == 1)
        #expect(viewModel.photosWithCards == 1)
        #expect(viewModel.failedIndices == [0, 1, 3])
    }

    @Test("buildCropsForSaving uses bbox to crop, multiplies by stepper quantity")
    func cropsRespectStepper() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(side: 400)]
        let bbox = BatchBoundingBox(x: 0.1, y: 0.1, w: 0.4, h: 0.4)  // 160×160 crop
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "Card", bbox: bbox)],
            payloadBytes: 0, analysis: nil, error: nil
        ))

        viewModel.setQuantity(at: 0, to: 3)
        let crops = viewModel.buildCropsForSaving()
        #expect(crops.count == 3)
        #expect(crops[0].width == 160)
        #expect(crops[0].height == 160)
    }

    @Test("buildCropsForSaving falls back to full source when bbox is missing")
    func cropFallsBackWithoutBbox() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(side: 300)]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "X", bbox: nil)],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        let crops = viewModel.buildCropsForSaving()
        #expect(crops.count == 1)
        #expect(crops[0].width == 300)
        #expect(crops[0].height == 300)
    }

    @Test("buildCropsForSaving rejects sub-50px bbox and falls back")
    func cropRejectsTinyBbox() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(side: 200)]
        let tiny = BatchBoundingBox(x: 0.1, y: 0.1, w: 0.1, h: 0.1)  // 20×20 crop
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "X", bbox: tiny)],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        let crops = viewModel.buildCropsForSaving()
        #expect(crops.count == 1)
        #expect(crops[0].width == 200)  // Fallback to full source
    }

    @Test("Reset clears all batch state back to selecting")
    func resetReturnsToSelecting() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "X")],
            payloadBytes: 500, analysis: "Notes", error: nil
        ))
        viewModel.setQuantity(at: 0, to: 5)

        viewModel.reset()

        #expect(viewModel.state == .selecting)
        #expect(viewModel.identifiedCards.isEmpty)
        #expect(viewModel.failedIndices.isEmpty)
        #expect(viewModel.payloadBytes == 0)
        #expect(viewModel.loadedImages.isEmpty)
        #expect(viewModel.analysis == nil)
        #expect(viewModel.quantities.isEmpty)
        #expect(viewModel.cardThumbnails.isEmpty)
    }

    // MARK: - Thumbnails

    @Test("cardThumbnails are populated from bbox crops at applyBatchResult")
    func thumbnailsFromBbox() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(side: 400)]
        let bbox = BatchBoundingBox(x: 0.1, y: 0.1, w: 0.4, h: 0.4)  // 160×160
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "Card", bbox: bbox)],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        let thumb = viewModel.cardThumbnails[0]
        #expect(thumb != nil)
        #expect(thumb?.width == 160)
        #expect(thumb?.height == 160)
    }

    @Test("cardThumbnails fall back to source image when bbox is nil")
    func thumbnailsFallBackWithoutBbox() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage(side: 300)]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "X", bbox: nil)],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        let thumb = viewModel.cardThumbnails[0]
        #expect(thumb != nil)
        #expect(thumb?.width == 300)  // Fell back to full source
    }

    @Test("Thumbnails are cleared when applyBatchResult delivers an error")
    func thumbnailsClearedOnError() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "X")],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        #expect(viewModel.cardThumbnails.count == 1)

        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [], payloadBytes: 0, analysis: nil, error: "rate limited"
        ))
        #expect(viewModel.cardThumbnails.isEmpty)
    }

    // MARK: - Learn-on-confirm

    @Test("addAllToCollection without deckRepository does not crash and does not learn")
    func addToCollectionNoRepoIsSafe() {
        let pipeline = BatchStubPipeline()
        let viewModel = BatchScanViewModel(pipeline: pipeline)
        viewModel.loadedImages = [makeTinyCGImage(side: 400)]
        let bbox = BatchBoundingBox(x: 0.1, y: 0.1, w: 0.4, h: 0.4)
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "Bolt", bbox: bbox)],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        viewModel.addAllToCollection()
        // No deckRepository — collection add is a no-op AND we skip learning since
        // we only learn when the user actually confirmed adds.
        #expect(viewModel.addedToCollection == 0)
    }

    @Test("learnIdentifiedCards calls pipeline once per detection that has a bbox")
    func learnFiresPerBboxCard() async {
        let pipeline = BatchStubPipeline()
        let viewModel = BatchScanViewModel(pipeline: pipeline)
        viewModel.loadedImages = [makeTinyCGImage(side: 400), makeTinyCGImage(side: 400)]
        let bbox = BatchBoundingBox(x: 0.1, y: 0.1, w: 0.4, h: 0.4)
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [
                makeIdentified(imageIndex: 0, name: "Bolt", bbox: bbox),
                makeIdentified(imageIndex: 1, name: "Counterspell", bbox: bbox),
            ],
            payloadBytes: 0, analysis: nil, error: nil
        ))

        await viewModel.learnIdentifiedCards()

        #expect(pipeline.learnedCardNames.sorted() == ["Bolt", "Counterspell"])
    }

    @Test("learnIdentifiedCards skips detections without a bbox")
    func learnSkipsWithoutBbox() async {
        let pipeline = BatchStubPipeline()
        let viewModel = BatchScanViewModel(pipeline: pipeline)
        viewModel.loadedImages = [makeTinyCGImage(side: 400)]
        let bbox = BatchBoundingBox(x: 0.1, y: 0.1, w: 0.4, h: 0.4)
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [
                makeIdentified(imageIndex: 0, name: "WithBbox", bbox: bbox),
                makeIdentified(imageIndex: 0, name: "NoBbox", bbox: nil),
            ],
            payloadBytes: 0, analysis: nil, error: nil
        ))

        await viewModel.learnIdentifiedCards()

        #expect(pipeline.learnedCardNames == ["WithBbox"])
    }

    @Test("totalValueUSD sums priced cards × stepper qty; skips unpriced")
    func totalValueSumsPricedCards() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [
                makeIdentified(imageIndex: 0, name: "Bolt", usd: "1.50"),
                makeIdentified(imageIndex: 0, name: "Counter", usd: "2.00"),
                makeIdentified(imageIndex: 0, name: "Unpriced", usd: nil),
            ],
            payloadBytes: 0, analysis: nil, error: nil
        ))

        // Default qty=1 each → 1.50 + 2.00 + 0 = 3.50
        #expect(abs(viewModel.totalValueUSD - 3.50) < 0.001)
        #expect(viewModel.hasAnyPrice)

        // Bumping the bolt stepper to 4 → 4×1.50 + 2.00 = 8.00
        viewModel.setQuantity(at: 0, to: 4)
        #expect(abs(viewModel.totalValueUSD - 8.00) < 0.001)
    }

    @Test("totalValueUSD updates when replaceCard swaps printing")
    func totalValueRespondsToReplaceCard() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "Bolt", usd: "1.00")],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        #expect(abs(viewModel.totalValueUSD - 1.00) < 0.001)

        // Fix flow swaps to a more expensive printing.
        let pricier = makeBatchCard(name: "Bolt", set: "p3k", collector: "42", usd: "120.00")
        viewModel.replaceCard(at: 0, with: pricier)
        #expect(abs(viewModel.totalValueUSD - 120.00) < 0.001)
    }

    @Test("hasAnyPrice is false when every card lacks a price")
    func hasAnyPriceFalseForUnpricedBatch() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [
                makeIdentified(imageIndex: 0, name: "A"),
                makeIdentified(imageIndex: 0, name: "B"),
            ],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        #expect(viewModel.hasAnyPrice == false)
        #expect(viewModel.totalValueUSD == 0)
    }

    // MARK: - Foil toggle

    @Test("Foil toggle defaults off; flipping it switches the unit price to usdFoil")
    @MainActor
    func foilToggleSwitchesPrice() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [
                makeIdentified(imageIndex: 0, name: "Spellstutter Sprite",
                               usd: "5.89", usdFoil: "30.45",
                               finishes: ["nonfoil", "foil"]),
            ],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        // Default: nonfoil
        #expect(viewModel.isFoil(at: 0) == false)
        #expect(viewModel.unitPriceUSD(at: 0) == 5.89)
        #expect(abs(viewModel.totalValueUSD - 5.89) < 0.001)

        // Flip to foil — the user just told us these cards are all foil.
        viewModel.toggleFoil(at: 0)
        #expect(viewModel.isFoil(at: 0) == true)
        #expect(viewModel.unitPriceUSD(at: 0) == 30.45)
        #expect(abs(viewModel.totalValueUSD - 30.45) < 0.001)
    }

    @Test("Foil-only printings auto-default to foil and lock the toggle")
    @MainActor
    func foilOnlyAutoDefaultsAndLocks() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [
                // FNM-style print: foil-only, no nonfoil USD.
                makeIdentified(imageIndex: 0, name: "Spellstutter Sprite",
                               usd: nil, usdFoil: "30.45",
                               finishes: ["foil"]),
            ],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        #expect(viewModel.foilOnly(at: 0) == true)
        #expect(viewModel.isFoil(at: 0) == true)            // auto-on
        #expect(viewModel.unitPriceUSD(at: 0) == 30.45)
        // Attempting to switch off should be a no-op for foil-only.
        viewModel.setFoil(at: 0, to: false)
        #expect(viewModel.isFoil(at: 0) == true)
    }

    @Test("totalValueUSD respects per-row foil flags across mixed batch")
    @MainActor
    func totalValueRespectsMixedFoilFlags() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [
                makeIdentified(imageIndex: 0, name: "Lorwyn Sprite",
                               usd: "5.89", usdFoil: "30.45",
                               finishes: ["nonfoil", "foil"]),
                makeIdentified(imageIndex: 0, name: "Plain Common",
                               usd: "0.10", usdFoil: "0.50",
                               finishes: ["nonfoil", "foil"]),
            ],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        // Mark only the first row foil.
        viewModel.setFoil(at: 0, to: true)
        // Total = 30.45 (foil) + 0.10 (nonfoil) = 30.55
        #expect(abs(viewModel.totalValueUSD - 30.55) < 0.001)
    }

    @Test("Foil toggle survives Fix-driven replaceCard, but foil-only forces on")
    @MainActor
    func foilFlagSurvivesReplaceCard() {
        let viewModel = BatchScanViewModel(pipeline: BatchStubPipeline())
        viewModel.loadedImages = [makeTinyCGImage()]
        viewModel.applyBatchResult(BatchIdentificationResult(
            cards: [makeIdentified(imageIndex: 0, name: "A", usd: "1.00", usdFoil: "10.00")],
            payloadBytes: 0, analysis: nil, error: nil
        ))
        viewModel.setFoil(at: 0, to: true)

        // Replace with a print that's also nonfoil-capable — foil flag retained.
        let normal = makeBatchCard(name: "B", usd: "2.00", usdFoil: "20.00",
                                   finishes: ["nonfoil", "foil"])
        viewModel.replaceCard(at: 0, with: normal)
        #expect(viewModel.isFoil(at: 0) == true)
        #expect(viewModel.unitPriceUSD(at: 0) == 20.00)

        // Replace with a foil-only print — flag forced on regardless of prior state.
        viewModel.setFoil(at: 0, to: false)   // pretend user toggled off
        let foilOnly = makeBatchCard(name: "C", usd: nil, usdFoil: "30.45",
                                     finishes: ["foil"])
        viewModel.replaceCard(at: 0, with: foilOnly)
        #expect(viewModel.isFoil(at: 0) == true)
        #expect(viewModel.foilOnly(at: 0) == true)
    }
}
