import Foundation
import SwiftData

// MARK: - Deck List Repository

/// Manages user-owned decks, purchase items, and orders.
/// Uses a single shared `ModelContext` so that mutations propagate to the
/// `@Model` instances the views are observing — no per-call fresh contexts,
/// no stale-mirror @State workarounds.
@MainActor
final class DeckListRepository {

    private let modelContainer: ModelContainer
    private(set) var context: ModelContext

    /// UserDefaults flag for the one-shot quantity-split migration.
    private static let splitMigrationKey = "deckItemsSplitMigration_v1_done"

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.context = ModelContext(modelContainer)
        runSplitMigrationIfNeeded()
    }

    /// One-time backfill: walks every PurchaseItem with a nil
    /// `priceAtAddUSD` snapshot and fills it in by looking up the live
    /// Scryfall price for that printing. Runs once per install, gated by
    /// UserDefaults. Uses the passed-in `cardRepository` for lookups.
    ///
    /// Idempotent — safe to call from any screen's onAppear / .task. The
    /// flag prevents duplicate work after the first successful run.
    func backfillPriceSnapshotsIfNeeded(cardRepository: CardRepositoryProtocol) async {
        let key = "priceAtAddBackfill_v1_done"
        if UserDefaults.standard.bool(forKey: key) { return }

        let descriptor = FetchDescriptor<PurchaseItem>(
            predicate: #Predicate<PurchaseItem> { $0.priceAtAddUSD == nil }
        )
        guard let items = try? context.fetch(descriptor), !items.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        // Cache lookups so we don't refetch the same printing repeatedly.
        var priceCache: [String: Double?] = [:]
        let now = Date()
        for item in items {
            let cacheKey = "\(item.setCode)|\(item.collectorNumber)"
            let cached: Double?
            if let hit = priceCache[cacheKey] {
                cached = hit
            } else {
                let card = try? await cardRepository.fetchCard(
                    set: item.setCode,
                    collectorNumber: item.collectorNumber
                )
                if let usdString = card?.prices.usd, let usd = Double(usdString) {
                    priceCache[cacheKey] = usd
                    cached = usd
                } else {
                    priceCache[cacheKey] = nil
                    cached = nil
                }
            }
            if let cached {
                item.priceAtAddUSD = cached
                item.priceAtAddDate = now
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// One-time migration: splits legacy items with `quantity > 1` into N
    /// individual copies. Runs once per install (gated by UserDefaults).
    private func runSplitMigrationIfNeeded() {
        if UserDefaults.standard.bool(forKey: Self.splitMigrationKey) { return }
        let descriptor = FetchDescriptor<PurchaseItem>(
            predicate: #Predicate<PurchaseItem> { $0.quantity > 1 }
        )
        guard let items = try? context.fetch(descriptor), !items.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.splitMigrationKey)
            return
        }
        for item in items {
            let extras = item.quantity - 1
            for _ in 0..<extras {
                let copy = PurchaseItem(
                    cardName: item.cardName,
                    setCode: item.setCode,
                    setName: item.setName,
                    collectorNumber: item.collectorNumber,
                    scryfallID: item.scryfallID,
                    manaCost: item.manaCost,
                    quantity: 1,
                    deck: item.deck
                )
                copy.zone = item.zone
                copy.statusRaw = item.statusRaw
                copy.store = item.store
                copy.purchaseURL = item.purchaseURL
                copy.pricePaid = item.pricePaid
                copy.notes = item.notes
                copy.orderedAt = item.orderedAt
                copy.arrivedAt = item.arrivedAt
                context.insert(copy)
            }
            item.quantity = 1
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: Self.splitMigrationKey)
    }

    // MARK: - Decks

    func fetchAllDecks() throws -> [DeckList] {
        let descriptor = FetchDescriptor<DeckList>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchDeck(id: UUID) throws -> DeckList? {
        let descriptor = FetchDescriptor<DeckList>(
            predicate: #Predicate<DeckList> { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func createDeck(name: String, format: String? = nil) throws -> DeckList {
        let deck = DeckList(name: name, format: format)
        context.insert(deck)
        try context.save()
        return deck
    }

    func deleteDeck(_ deck: DeckList) throws {
        context.delete(deck)
        try context.save()
    }

    func renameDeck(_ deck: DeckList, name: String, format: String?) throws {
        deck.name = name
        deck.format = format
        try context.save()
    }

    /// Sets the user-chosen icon for a deck. Pass nil to clear the override
    /// and return to the algorithmic picker.
    func setDeckIcon(_ deck: DeckList, scryfallID: String?) throws {
        deck.customSignatureScryfallID = scryfallID
        try context.save()
    }

    // MARK: - Purchase Items

    /// Fetches all purchase items for a given deck ID.
    /// (The legacy split migration runs once at init, not on every fetch.)
    func fetchItems(deckID: UUID) throws -> [PurchaseItem] {
        let descriptor = FetchDescriptor<PurchaseItem>(
            predicate: #Predicate<PurchaseItem> { $0.deck?.id == deckID },
            sortBy: [SortDescriptor(\.addedAt)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetches every PurchaseItem across every deck. Used by the global
    /// "New Order" flow where the user pastes a confirmation that may
    /// span multiple decks.
    func fetchAllItems() throws -> [PurchaseItem] {
        let descriptor = FetchDescriptor<PurchaseItem>(
            sortBy: [SortDescriptor(\.addedAt)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetches PurchaseItems with a specific status (avoids loading entire table).
    func fetchItemsByStatus(_ status: PurchaseStatus) throws -> [PurchaseItem] {
        let statusRaw = status.rawValue
        let descriptor = FetchDescriptor<PurchaseItem>(
            predicate: #Predicate<PurchaseItem> { $0.statusRaw == statusRaw },
            sortBy: [SortDescriptor(\.cardName)]
        )
        return try context.fetch(descriptor)
    }

    /// Total amount spent on a deck, grouped by currency. Items without a
    /// recorded price are skipped. Items without a currency are bucketed as
    /// "USD" (the legacy default before the field was added).
    /// Returns a dictionary keyed by currency code.
    func totalSpent(deckID: UUID) throws -> [String: Double] {
        let descriptor = FetchDescriptor<PurchaseItem>(
            predicate: #Predicate<PurchaseItem> { $0.deck?.id == deckID }
        )
        let items = try context.fetch(descriptor)
        var totals: [String: Double] = [:]
        for item in items {
            guard let price = item.pricePaid else { continue }
            let key = item.currency ?? "USD"
            totals[key, default: 0] += price
        }
        return totals
    }

    /// Adds N individual copies of a card to a deck (one PurchaseItem per copy).
    /// This enables per-card status tracking. `isFoil` is stamped on every
    /// copy created by this call — mixed foil/nonfoil for the same card
    /// requires two calls.
    func addItem(card: Card, quantity: Int, to deck: DeckList, zone: String = "mainboard", isFoil: Bool = false) throws -> PurchaseItem {
        var first: PurchaseItem?
        for _ in 0..<max(1, quantity) {
            let item = PurchaseItem.from(card: card, quantity: 1, deck: deck, zone: zone, isFoil: isFoil)
            context.insert(item)
            if first == nil { first = item }
        }
        try context.save()
        return first!
    }

    /// Adds N individual copies of a card by name only (no resolved Card
    /// needed). Used when building a reference decklist where some cards
    /// may not be in the local database.
    @discardableResult
    func addItemByName(
        cardName: String,
        quantity: Int,
        status: PurchaseStatus = .needed,
        zone: String = "mainboard",
        to deck: DeckList
    ) throws -> PurchaseItem {
        var first: PurchaseItem?
        for _ in 0..<max(1, quantity) {
            let item = PurchaseItem(
                cardName: cardName,
                setCode: "",
                setName: "",
                collectorNumber: "",
                scryfallID: UUID().uuidString,
                quantity: 1,
                deck: deck
            )
            item.zone = zone
            item.statusRaw = status.rawValue
            context.insert(item)
            if first == nil { first = item }
        }
        try context.save()
        return first!
    }

    func updateItem(
        _ item: PurchaseItem,
        status: PurchaseStatus? = nil,
        store: String? = nil,
        purchaseURL: String? = nil,
        pricePaid: Double? = nil,
        currency: String? = nil,
        notes: String? = nil,
        quantity: Int? = nil,
        orderedAt: Date? = nil
    ) throws {
        // Capture the prior status so we can detect a Needed/Ordered → Arrived
        // transition and cascade the new copy into the collection.
        let wasArrived = item.status == .arrived
        if let status {
            item.status = status
            switch status {
            case .ordered:
                if item.orderedAt == nil { item.orderedAt = Date() }
            case .arrived:
                if item.arrivedAt == nil { item.arrivedAt = Date() }
                if item.orderedAt == nil { item.orderedAt = Date() }
            case .needed:
                item.orderedAt = nil
                item.arrivedAt = nil
            case .owned:
                break // No date tracking needed — matched from collection
            }
        }
        if let store { item.store = store.isEmpty ? nil : store }
        if let purchaseURL { item.purchaseURL = purchaseURL.isEmpty ? nil : purchaseURL }
        if let pricePaid { item.pricePaid = pricePaid }
        if let currency { item.currency = currency.isEmpty ? nil : currency }
        if let notes { item.notes = notes.isEmpty ? nil : notes }
        if let quantity { item.quantity = quantity }
        // Caller-supplied purchase date overrides the auto-assignment in the
        // status branch above. Lets edit screens record a historical date
        // without having to flip the status first.
        if let orderedAt { item.orderedAt = orderedAt }
        try context.save()

        // Cascade to collection on transition INTO arrived. Skips when the
        // item was already arrived (idempotent — repeated saves don't double-
        // count). No subtraction on transition out — the user might still
        // own physical copies even after resetting an item to Needed, so we
        // leave that judgment to them via the Collection screen.
        if let status, status == .arrived, !wasArrived {
            try addToCollectionFromItem(item, quantity: 1)
        }
    }

    /// Backfills the manaCost / typeLine fields for an existing item.
    func updateMetadata(_ item: PurchaseItem, manaCost: String?, typeLine: String?) throws {
        if let manaCost { item.manaCost = manaCost }
        if let typeLine { item.typeLine = typeLine }
        try context.save()
    }

    /// Updates a PurchaseItem's printing fields to point to a different printing
    /// of the same card.
    func changePrinting(_ item: PurchaseItem, to card: Card) throws {
        item.cardName = card.name
        item.scryfallID = card.scryfallID
        item.setCode = card.set.code
        item.setName = card.set.name
        item.collectorNumber = card.collectorNumber
        item.manaCost = card.manaCost
        item.typeLine = card.typeLine
        try context.save()
    }

    /// Moves one or more items to a different zone (e.g. "mainboard" ↔ "sideboard").
    func moveItems(_ items: [PurchaseItem], toZone zone: String) throws {
        for item in items {
            item.zone = zone
        }
        try context.save()
    }

    func deleteItem(_ item: PurchaseItem) throws {
        context.delete(item)
        try context.save()
    }

    // MARK: - Orders

    /// Creates a new Order, marks the given items as `.ordered`, links them
    /// to the order, and writes the order's currency + per-item price onto each.
    /// `prices` is a parallel array to `items` (one price per item, in the
    /// order's currency). Items in `prices` may be nil to skip price recording.
    @discardableResult
    func createOrder(
        store: String,
        orderedAt: Date,
        eta: Date?,
        purchaseURL: String?,
        notes: String?,
        currency: String,
        totalDue: Double?,
        items: [PurchaseItem],
        prices: [Double?]
    ) throws -> Order {
        precondition(items.count == prices.count, "items and prices must have equal length")
        let order = Order(
            store: store,
            orderedAt: orderedAt,
            eta: eta,
            purchaseURL: purchaseURL,
            notes: notes,
            currency: currency,
            totalDue: totalDue
        )
        context.insert(order)
        for (index, item) in items.enumerated() {
            item.status = .ordered
            item.orderedAt = orderedAt
            item.store = store
            item.purchaseURL = purchaseURL
            item.currency = currency
            if let price = prices[index] {
                item.pricePaid = price
            }
            item.order = order
        }
        try context.save()
        return order
    }

    func fetchOrders(deckID: UUID? = nil) throws -> [Order] {
        let descriptor = FetchDescriptor<Order>(
            sortBy: [SortDescriptor(\.orderedAt, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        guard let deckID else { return all }
        return all.filter { order in
            order.items.contains { $0.deck?.id == deckID }
        }
    }

    /// Updates the editable header fields on an Order. Cascades store /
    /// orderedAt / currency / purchaseURL changes onto every linked item.
    func updateOrder(
        _ order: Order,
        store: String,
        orderedAt: Date,
        eta: Date?,
        purchaseURL: String?,
        notes: String?,
        currency: String,
        totalDue: Double?
    ) throws {
        order.store = store
        order.orderedAt = orderedAt
        order.eta = eta
        order.purchaseURL = purchaseURL
        order.notes = notes
        order.currency = currency
        order.totalDue = totalDue
        for item in order.items {
            item.store = store
            item.purchaseURL = purchaseURL
            item.currency = currency
            if item.status != .needed {
                item.orderedAt = orderedAt
            }
        }
        try context.save()
    }

    /// Marks every item linked to this order as `.arrived` and adds the
    /// arrived copies to the collection (so the user's "what I own" view
    /// stays in sync with the order workflow).
    func markOrderArrived(_ order: Order) throws {
        let now = Date()
        // Group items by printing so we add (qty: N) once instead of N times.
        var addsByScryfallID: [String: (item: PurchaseItem, count: Int)] = [:]
        for item in order.items {
            // Only add to collection if this is a NEW arrival — already-arrived
            // items would otherwise double-count if Mark All Arrived is hit twice.
            let alreadyArrived = item.status == .arrived
            item.status = .arrived
            if item.arrivedAt == nil { item.arrivedAt = now }
            if item.orderedAt == nil { item.orderedAt = order.orderedAt }
            if !alreadyArrived {
                if var entry = addsByScryfallID[item.scryfallID] {
                    entry.count += 1
                    addsByScryfallID[item.scryfallID] = entry
                } else {
                    addsByScryfallID[item.scryfallID] = (item: item, count: 1)
                }
            }
        }
        try context.save()
        // Add to collection — uses the existing PurchaseItem snapshot fields
        // since we don't have a Card here.
        for (_, entry) in addsByScryfallID {
            try addToCollectionFromItem(entry.item, quantity: entry.count)
        }
    }

    /// Increments the collection from a PurchaseItem's snapshot fields.
    /// Used when we don't have a `Card` available (e.g. cascading from an
    /// order arrival). Same dedup behavior as `addToCollection(card:)`.
    @discardableResult
    private func addToCollectionFromItem(_ item: PurchaseItem, quantity: Int) throws -> CollectionItem {
        let scryfallID = item.scryfallID
        let descriptor = FetchDescriptor<CollectionItem>(
            predicate: #Predicate<CollectionItem> { $0.scryfallID == scryfallID }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.quantity += quantity
            try context.save()
            return existing
        }
        let collectionItem = CollectionItem(
            cardName: item.cardName,
            setCode: item.setCode,
            setName: item.setName,
            collectorNumber: item.collectorNumber,
            scryfallID: item.scryfallID,
            manaCost: item.manaCost,
            typeLine: item.typeLine,
            quantity: quantity
        )
        context.insert(collectionItem)
        try context.save()
        return collectionItem
    }

    /// Deletes the order and resets all of its items back to `.needed`.
    /// The items themselves are NOT deleted — only the bulk-order grouping.
    func deleteOrder(_ order: Order, resetItemsToNeeded: Bool = true) throws {
        if resetItemsToNeeded {
            for item in order.items {
                item.status = .needed
                item.orderedAt = nil
                item.arrivedAt = nil
                item.pricePaid = nil
                item.currency = nil
                item.order = nil
            }
        }
        context.delete(order)
        try context.save()
    }

    // MARK: - Collection

    /// Returns every CollectionItem the user owns.
    func fetchCollection() throws -> [CollectionItem] {
        let descriptor = FetchDescriptor<CollectionItem>(
            sortBy: [SortDescriptor(\.cardName)]
        )
        return try context.fetch(descriptor)
    }

    /// Adds N copies of the given card to the collection. If a CollectionItem
    /// already exists for the same set + collector number, increments its
    /// quantity instead of creating a duplicate row.
    @discardableResult
    func addToCollection(card: Card, quantity: Int = 1, foilQuantity: Int = 0) throws -> CollectionItem {
        let scryfallID = card.scryfallID
        let descriptor = FetchDescriptor<CollectionItem>(
            predicate: #Predicate<CollectionItem> { $0.scryfallID == scryfallID }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.quantity += quantity
            existing.foilQuantity += foilQuantity
            try context.save()
            return existing
        }
        let item = CollectionItem.from(card: card, quantity: quantity, foilQuantity: foilQuantity)
        context.insert(item)
        try context.save()
        return item
    }

    /// Sets the absolute quantity on a CollectionItem (not delta).
    /// Removes the item entirely if `quantity` becomes 0.
    func setCollectionQuantity(_ item: CollectionItem, quantity: Int, foilQuantity: Int? = nil) throws {
        if quantity <= 0 {
            context.delete(item)
        } else {
            item.quantity = quantity
            if let foilQuantity {
                item.foilQuantity = max(0, min(foilQuantity, quantity))
            }
        }
        try context.save()
    }

    func deleteCollectionItem(_ item: CollectionItem) throws {
        context.delete(item)
        try context.save()
    }

    /// Returns total copies the user owns of a specific printing.
    /// Used by deck-detail / shopping-list to show "X owned of Y needed."
    func ownedQuantity(setCode: String, collectorNumber: String) throws -> Int {
        let descriptor = FetchDescriptor<CollectionItem>(
            predicate: #Predicate<CollectionItem> {
                $0.setCode == setCode && $0.collectorNumber == collectorNumber
            }
        )
        return try context.fetch(descriptor).first?.quantity ?? 0
    }

    /// Returns a `[scryfallID: ownedCount]` map for fast joins.
    func ownedQuantitiesByScryfallID() throws -> [String: Int] {
        let descriptor = FetchDescriptor<CollectionItem>()
        let items = try context.fetch(descriptor)
        var result: [String: Int] = [:]
        for item in items {
            result[item.scryfallID] = item.quantity
        }
        return result
    }

    /// Returns a `[cardName: totalQuantity]` map across all printings.
    /// Used by the Lands and cEDH Staples lists to show "you own 2×"
    /// badges next to each card regardless of which printing is owned.
    func ownedQuantitiesByName() throws -> [String: Int] {
        let descriptor = FetchDescriptor<CollectionItem>()
        let items = try context.fetch(descriptor)
        var result: [String: Int] = [:]
        for item in items {
            result[item.cardName, default: 0] += item.quantity
        }
        return result
    }

    /// Returns per-printing ownership data grouped by card name.
    /// Each entry maps a card name to an array of (setCode, quantity) pairs.
    /// Used by collectible land lists that need set-aware collection matching.
    func ownedDetailsByName() throws -> [String: [(setCode: String, setName: String, quantity: Int)]] {
        let descriptor = FetchDescriptor<CollectionItem>()
        let items = try context.fetch(descriptor)
        var result: [String: [(setCode: String, setName: String, quantity: Int)]] = [:]
        for item in items {
            result[item.cardName, default: []].append((setCode: item.setCode, setName: item.setName, quantity: item.quantity))
        }
        return result
    }

    // MARK: - Card Analyses

    /// Saves a card-list analysis with serialized results.
    @discardableResult
    func saveAnalysis(title: String, rawCardList: String, results: [AnalysisFormatResult]) throws -> CardAnalysis {
        let data = try JSONEncoder().encode(results)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        let analysis = CardAnalysis(title: title, rawCardList: rawCardList, formatResultsJSON: json)
        context.insert(analysis)
        try context.save()
        return analysis
    }

    /// Fetches all saved analyses, newest first.
    func fetchAnalyses() throws -> [CardAnalysis] {
        let descriptor = FetchDescriptor<CardAnalysis>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Deletes a saved analysis.
    func deleteAnalysis(_ analysis: CardAnalysis) throws {
        context.delete(analysis)
        try context.save()
    }

    // MARK: - Store History (for autocomplete)

    /// Returns the unique list of stores the user has used, sorted by most recent.
    func recentStores() throws -> [String] {
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
