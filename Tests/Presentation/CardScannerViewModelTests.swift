import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import MTGCardScanner

// MARK: - Mocks

/// A stubbed text recognizer for ViewModel tests.
struct StubbedTextRecognizer: TextRecognizerProtocol {

    var results: [ScanResult]?
    var errorToThrow: Error?

    func recognizeText(in image: CGImage) async throws -> [ScanResult] {
        if let errorToThrow {
            throw errorToThrow
        }
        return results ?? []
    }
}

/// A stubbed card repository that returns a predefined card or throws.
struct StubbedCardRepository: CardRepositoryProtocol {

    var identifyResult: Card?
    var identifyError: Error?
    var searchResults: [Card] = []

    func identifyCard(name: String) async throws -> Card {
        if let error = identifyError {
            throw error
        }
        guard let card = identifyResult else {
            throw CardRepositoryError.cardNotFound
        }
        return card
    }

    func fetchCard(set: String, collectorNumber: String) async throws -> Card {
        guard let card = identifyResult else {
            throw CardRepositoryError.cardNotFound
        }
        return card
    }

    func searchCards(query: String) async throws -> [Card] {
        return searchResults
    }

    func findAllPrintings(name: String) async throws -> [Card] {
        return searchResults
    }

    func findVariants(name: String, setCode: String) async throws -> [Card] {
        return searchResults
    }
}

// MARK: - Test Helpers

private func makeTestCard(
    name: String = "Lightning Bolt",
    id: UUID = UUID()
) -> Card {
    Card(
        id: id,
        scryfallID: "abc-123",
        name: name,
        manaCost: "{R}",
        typeLine: "Instant",
        oracleText: "Lightning Bolt deals 3 damage to any target.",
        set: SetInfo(
            code: "2ed",
            name: "Unlimited Edition",
            setType: "core",
            iconSVGURI: nil,
            releasedAt: "1993-12-01"
        ),
        collectorNumber: "161",
        rarity: .common,
        artist: "Test Artist",
        releasedAt: nil,
        borderColor: nil,
        frame: nil,
        illustrationID: nil,
        edhrecRank: nil,
        prices: CardPrices(usd: "1.50", usdFoil: nil, eur: "1.20", eurFoil: nil, tix: nil),
        legalities: FormatLegality([
            "standard": .notLegal,
            "modern": .legal,
            "legacy": .legal,
            "commander": .legal,
            "pioneer": .notLegal
        ]),
        imageURIs: ["normal": "https://example.com/bolt.jpg"],
        relatedPrintingsURI: nil
    )
}

// MARK: - Mock Pipeline

struct MockPipeline: CardIdentificationPipelineProtocol {
    var resultCard: Card?
    var resultCards: [Card]?

    func identify(imageData: Data) async -> Card? {
        guard !imageData.isEmpty, imageData.count > 2 else { return nil }
        return resultCard
    }

    func identifyCropped(cardImage: CGImage) async -> Card? {
        return resultCard
    }

    func identifyAll(imageData: Data) async -> [Card] {
        guard !imageData.isEmpty, imageData.count > 2 else { return [] }
        if let cards = resultCards { return cards }
        if let card = resultCard { return [card] }
        return []
    }
}

// MARK: - Tests

@Suite("CardScannerViewModel Tests")
struct CardScannerViewModelTests {

    @Test("Initial state is idle")
    func initialStateIsIdle() {
        let viewModel = CardScannerViewModel(
            pipeline: MockPipeline()
        )

        #expect(viewModel.scanState == .idle)
        #expect(viewModel.scannedCards.isEmpty)
        #expect(viewModel.processingProgress == 0)
    }

    @Test("processSelectedPhotos with empty array sets completed with empty cards")
    @MainActor
    func processEmptyPhotosCompletesEmpty() async {
        let viewModel = CardScannerViewModel(
            pipeline: MockPipeline()
        )

        await viewModel.processSelectedPhotos([])

        #expect(viewModel.scanState == .completed([]))
        #expect(viewModel.scannedCards.isEmpty)
    }

    @Test("resetScan returns to idle and clears cards")
    @MainActor
    func resetScanReturnsToIdle() async {
        let viewModel = CardScannerViewModel(
            pipeline: MockPipeline()
        )

        // Simulate a completed state by processing empty photos first
        await viewModel.processSelectedPhotos([])
        #expect(viewModel.scanState == .completed([]))

        viewModel.resetScan()
        #expect(viewModel.scanState == .idle)
        #expect(viewModel.scannedCards.isEmpty)
        #expect(viewModel.processingProgress == 0)
    }

    @Test("processImageData recognizes card from valid image data")
    @MainActor
    func processImageDataRecognizesCard() async {
        let card = makeTestCard()
        let viewModel = CardScannerViewModel(
            pipeline: MockPipeline(resultCard: card)
        )

        let imageData = makeTestPNGData(width: 100, height: 100)!
        let result = await viewModel.processImageData(imageData)

        #expect(result != nil)
        #expect(result?.name == "Lightning Bolt")
    }

    @Test("processImageData returns nil for invalid image data")
    @MainActor
    func processImageDataReturnsNilForInvalidData() async {
        let viewModel = CardScannerViewModel(
            pipeline: MockPipeline(resultCard: makeTestCard())
        )

        // MockPipeline returns nil for data with count <= 2
        let result = await viewModel.processImageData(Data([0x00, 0x01]))

        #expect(result == nil)
    }

    @Test("processImageData returns nil when pipeline fails")
    @MainActor
    func processImageDataReturnsNilOnPipelineFailure() async {
        let viewModel = CardScannerViewModel(
            pipeline: MockPipeline(resultCard: nil)
        )

        let imageData = makeTestPNGData(width: 100, height: 100)!
        let result = await viewModel.processImageData(imageData)

        #expect(result == nil)
    }

    // MARK: - ScanState Equatable Tests

    @Test("ScanState.idle equals idle")
    func scanStateIdleEquatable() {
        #expect(ScanState.idle == ScanState.idle)
    }

    @Test("ScanState.processing equality compares current and total")
    func scanStateProcessingEquatable() {
        #expect(ScanState.processing(current: 1, total: 5) == ScanState.processing(current: 1, total: 5))
        #expect(ScanState.processing(current: 1, total: 5) != ScanState.processing(current: 2, total: 5))
    }

    @Test("ScanState.completed equality compares card count")
    func scanStateCompletedEquatable() {
        let card = makeTestCard()
        #expect(ScanState.completed([card]) == ScanState.completed([card]))
        #expect(ScanState.completed([]) != ScanState.completed([card]))
    }

    @Test("ScanState.error equality compares messages")
    func scanStateErrorEquatable() {
        #expect(ScanState.error("fail") == ScanState.error("fail"))
        #expect(ScanState.error("a") != ScanState.error("b"))
    }
}

// MARK: - Test Image Helper

private func makeTestPNGData(width: Int, height: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.setFillColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 1.0)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = context.makeImage() else { return nil }
    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        mutableData as CFMutableData,
        "public.png" as CFString,
        1,
        nil
    ) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return mutableData as Data
}
