import Foundation
import SwiftData

// MARK: - Deck List Repository

/// Manages user-owned decks and purchase items.
/// All persistence operations route through SwiftData's ModelContext.
@MainActor
final class DeckListRepository {

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Decks

    func fetchAllDecks() throws -> [DeckList] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<DeckList>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchDeck(id: UUID) throws -> DeckList? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<DeckList>(
            predicate: #Predicate<DeckList> { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func createDeck(name: String, format: String? = nil) throws -> DeckList {
        let context = ModelContext(modelContainer)
        let deck = DeckList(name: name, format: format)
        context.insert(deck)
        try context.save()
        return deck
    }

    func deleteDeck(_ deck: DeckList) throws {
        let context = ModelContext(modelContainer)
        let id = deck.id
        let descriptor = FetchDescriptor<DeckList>(
            predicate: #Predicate<DeckList> { $0.id == id }
        )
        guard let target = try context.fetch(descriptor).first else { return }
        context.delete(target)
        try context.save()
    }

    func renameDeck(_ deck: DeckList, name: String, format: String?) throws {
        let context = ModelContext(modelContainer)
        let id = deck.id
        let descriptor = FetchDescriptor<DeckList>(
            predicate: #Predicate<DeckList> { $0.id == id }
        )
        guard let target = try context.fetch(descriptor).first else { return }
        target.name = name
        target.format = format
        try context.save()
    }

    // MARK: - Purchase Items

    func addItem(card: Card, quantity: Int, to deck: DeckList) throws -> PurchaseItem {
        let context = ModelContext(modelContainer)
        let deckID = deck.id
        let descriptor = FetchDescriptor<DeckList>(
            predicate: #Predicate<DeckList> { $0.id == deckID }
        )
        guard let target = try context.fetch(descriptor).first else {
            throw NSError(domain: "DeckListRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Deck not found"])
        }
        let item = PurchaseItem.from(card: card, quantity: quantity, deck: target)
        context.insert(item)
        try context.save()
        return item
    }

    func updateItem(
        _ item: PurchaseItem,
        status: PurchaseStatus? = nil,
        store: String? = nil,
        purchaseURL: String? = nil,
        pricePaid: Double? = nil,
        notes: String? = nil,
        quantity: Int? = nil
    ) throws {
        let context = ModelContext(modelContainer)
        let id = item.id
        let descriptor = FetchDescriptor<PurchaseItem>(
            predicate: #Predicate<PurchaseItem> { $0.id == id }
        )
        guard let target = try context.fetch(descriptor).first else { return }

        if let status {
            target.status = status
            switch status {
            case .ordered:
                if target.orderedAt == nil { target.orderedAt = Date() }
            case .arrived:
                if target.arrivedAt == nil { target.arrivedAt = Date() }
                if target.orderedAt == nil { target.orderedAt = Date() }
            case .needed:
                target.orderedAt = nil
                target.arrivedAt = nil
            }
        }
        if let store { target.store = store.isEmpty ? nil : store }
        if let purchaseURL { target.purchaseURL = purchaseURL.isEmpty ? nil : purchaseURL }
        if let pricePaid { target.pricePaid = pricePaid }
        if let notes { target.notes = notes.isEmpty ? nil : notes }
        if let quantity { target.quantity = quantity }

        try context.save()
    }

    func deleteItem(_ item: PurchaseItem) throws {
        let context = ModelContext(modelContainer)
        let id = item.id
        let descriptor = FetchDescriptor<PurchaseItem>(
            predicate: #Predicate<PurchaseItem> { $0.id == id }
        )
        guard let target = try context.fetch(descriptor).first else { return }
        context.delete(target)
        try context.save()
    }

    // MARK: - Store History (for autocomplete)

    /// Returns the unique list of stores the user has used, sorted by most recent.
    func recentStores() throws -> [String] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PurchaseItem>(
            sortBy: [SortDescriptor(\.orderedAt, order: .reverse)]
        )
        let items = try context.fetch(descriptor)
        var seen: Set<String> = []
        var result: [String] = []
        for item in items {
            if let store = item.store, !store.isEmpty, !seen.contains(store) {
                seen.insert(store)
                result.append(store)
            }
        }
        return result
    }
}
