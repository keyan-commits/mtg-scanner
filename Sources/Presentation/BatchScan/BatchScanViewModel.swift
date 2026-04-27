import SwiftUI
import PhotosUI

@Observable
@MainActor
final class BatchScanViewModel {
    let pipeline: CardIdentificationPipelineProtocol
    let cardRepository: CardRepositoryProtocol?
    let deckRepository: DeckListRepository?

    enum State: Equatable {
        case selecting
        case processing(current: Int, total: Int)
        case results
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.selecting, .selecting): return true
            case (.processing(let a, let b), .processing(let c, let d)): return a == c && b == d
            case (.results, .results): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    var state: State = .selecting
    var selectedPhotos: [PhotosPickerItem] = []
    var loadedImages: [CGImage] = []
    var identifiedCards: [(index: Int, card: Card)] = []
    var failedIndices: [Int] = []
    var payloadBytes: Int = 0
    var addedToCollection: Int = 0
    var addedToDeck: DeckList?

    init(pipeline: CardIdentificationPipelineProtocol,
         cardRepository: CardRepositoryProtocol? = nil,
         deckRepository: DeckListRepository? = nil) {
        self.pipeline = pipeline
        self.cardRepository = cardRepository
        self.deckRepository = deckRepository
    }

    var identifiedCount: Int { identifiedCards.count }
    var totalPhotos: Int { loadedImages.count }
    var payloadMB: String {
        ByteCountFormatter.string(fromByteCount: Int64(payloadBytes), countStyle: .file)
    }

    func loadAndProcess() async {
        guard !selectedPhotos.isEmpty else { return }
        state = .processing(current: 0, total: selectedPhotos.count)

        // Load all photos as CGImages
        loadedImages = []
        for (i, item) in selectedPhotos.enumerated() {
            state = .processing(current: i + 1, total: selectedPhotos.count)
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data),
               let cgImage = uiImage.cgImage {
                loadedImages.append(cgImage)
            }
        }

        guard !loadedImages.isEmpty else {
            state = .error("Could not load any photos")
            return
        }

        // Send to Gemini batch
        state = .processing(current: loadedImages.count, total: loadedImages.count)
        let result = await pipeline.identifyBatch(images: loadedImages)
        identifiedCards = result.cards
        payloadBytes = result.payloadBytes

        // Find which indices had no match
        let matchedIndices = Set(identifiedCards.map(\.index))
        failedIndices = (0..<loadedImages.count).filter { !matchedIndices.contains($0) }

        state = .results
    }

    func addAllToCollection() {
        guard let repo = deckRepository else { return }
        var count = 0
        for (_, card) in identifiedCards {
            if let _ = try? repo.addToCollection(card: card) {
                count += 1
            }
        }
        addedToCollection = count
    }

    func createDeck(name: String) {
        guard let repo = deckRepository else { return }
        guard let deck = try? repo.createDeck(name: name) else { return }
        // Group by card name to set correct quantities
        var grouped: [String: (card: Card, count: Int)] = [:]
        for (_, card) in identifiedCards {
            if var entry = grouped[card.name] {
                entry.count += 1
                grouped[card.name] = entry
            } else {
                grouped[card.name] = (card: card, count: 1)
            }
        }
        for (_, entry) in grouped {
            _ = try? repo.addItem(card: entry.card, quantity: entry.count, to: deck)
        }
        addedToDeck = deck
    }

    func reset() {
        state = .selecting
        selectedPhotos = []
        loadedImages = []
        identifiedCards = []
        failedIndices = []
        payloadBytes = 0
        addedToCollection = 0
        addedToDeck = nil
    }
}
