import Testing
import Foundation
import SwiftData
@testable import MTGCardScanner

/// Integration tests for the For Sale layer on `DeckListRepository`.
/// Each test gets a fresh in-memory ModelContainer so state doesn't leak.
@Suite("Collection For Sale Tests")
@MainActor
struct CollectionForSaleTests {

    // MARK: - Setup

    private static func makeRepo() -> DeckListRepository {
        let schema = Schema([
            CardRecord.self,
            DeckList.self,
            PurchaseItem.self,
            Order.self,
            CollectionItem.self,
            CardAnalysis.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return DeckListRepository(modelContainer: container)
    }

    private static func makeCard(name: String = "Spellstutter Sprite",
                                 set: String = "lrw",
                                 collector: String = "89") -> Card {
        Card(
            scryfallID: "\(name)-\(set)-\(collector)",
            name: name,
            manaCost: "{1}{U}",
            typeLine: "Creature",
            oracleText: nil,
            set: SetInfo(code: set, name: set.uppercased(), setType: "expansion", iconSVGURI: nil, releasedAt: nil),
            collectorNumber: collector,
            rarity: .uncommon,
            artist: nil,
            releasedAt: nil,
            borderColor: nil,
            frame: nil,
            frameEffects: [],
            illustrationID: nil,
            edhrecRank: nil,
            prices: CardPrices(usd: "5.89", usdFoil: "30.45", eur: nil, eurFoil: nil, tix: nil, previousUsd: nil),
            legalities: FormatLegality([:]),
            imageURIs: [:],
            relatedPrintingsURI: nil,
            lang: "en",
            printedName: nil,
            promoTypes: [],
            finishes: ["nonfoil", "foil"]
        )
    }

    // MARK: - markForSale

    @Test("markForSale stamps listedAt + records asking prices for both finishes")
    func markForSaleHappyPath() throws {
        let repo = Self.makeRepo()
        let card = Self.makeCard()
        let item = try repo.addToCollection(card: card, quantity: 4, foilQuantity: 2)

        try repo.markForSale(
            item,
            nonfoilQuantity: 1,
            foilQuantity: 2,
            askingPriceUSD: 6.0,
            askingPriceFoilUSD: 32.0,
            listedOn: "Tambayan",
            notes: "PM for shipping"
        )

        #expect(item.forSaleNonfoilQuantity == 1)
        #expect(item.forSaleFoilQuantity == 2)
        #expect(item.forSaleQuantity == 3)
        #expect(item.askingPriceUSD == 6.0)
        #expect(item.askingPriceFoilUSD == 32.0)
        #expect(item.listedOn == "Tambayan")
        #expect(item.saleNotes == "PM for shipping")
        #expect(item.listedAt != nil)
        #expect(item.isListed == true)
    }

    @Test("markForSale clamps to available copies; can't sell what you don't own")
    func markForSaleClamps() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 4, foilQuantity: 2)
        // Try to list 99 nonfoil + 99 foil — gets clamped.
        try repo.markForSale(item, nonfoilQuantity: 99, foilQuantity: 99)
        #expect(item.forSaleNonfoilQuantity == 2)   // 4 - 2 = 2 nonfoil owned
        #expect(item.forSaleFoilQuantity == 2)      // 2 foil owned
    }

    @Test("markForSale with zero on both finishes clears all listing fields")
    func unmarkClearsListing() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 4, foilQuantity: 2)
        try repo.markForSale(item, nonfoilQuantity: 1, foilQuantity: 1,
                             askingPriceUSD: 6.0, listedOn: "Local", notes: "n")
        #expect(item.listedAt != nil)

        try repo.unmarkForSale(item)
        #expect(item.forSaleQuantity == 0)
        #expect(item.askingPriceUSD == nil)
        #expect(item.askingPriceFoilUSD == nil)
        #expect(item.listedAt == nil)
        #expect(item.listedOn == nil)
        #expect(item.saleNotes == nil)
    }

    // MARK: - recordSale

    @Test("recordSale decrements both quantity and forSale, increments soldQuantity")
    func recordSaleHappyPath() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 4, foilQuantity: 2)
        try repo.markForSale(item, nonfoilQuantity: 1, foilQuantity: 2,
                             askingPriceUSD: 6.0, askingPriceFoilUSD: 32.0)

        try repo.recordSale(item, isFoil: true, quantity: 1, soldPriceUSD: 30.0)
        #expect(item.foilQuantity == 1)
        #expect(item.quantity == 3)
        #expect(item.forSaleFoilQuantity == 1)
        #expect(item.soldFoilQuantity == 1)
        #expect(item.soldQuantity == 1)
        #expect(item.lastSoldPriceUSD == 30.0)
        #expect(item.lastSoldAt != nil)
    }

    @Test("recordSale clears listing metadata once nothing remains for sale")
    func recordSaleClearsWhenEmpty() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 1, foilQuantity: 1)
        try repo.markForSale(item, nonfoilQuantity: 0, foilQuantity: 1,
                             askingPriceFoilUSD: 32.0, listedOn: "Tambayan")
        try repo.recordSale(item, isFoil: true, quantity: 1, soldPriceUSD: 30.0)

        // The single foil copy is gone. Listing fields cleared.
        #expect(item.foilQuantity == 0)
        #expect(item.quantity == 0)
        #expect(item.forSaleQuantity == 0)
        #expect(item.askingPriceFoilUSD == nil)
        #expect(item.listedOn == nil)
        // But sales history is preserved — this is the differentiator.
        #expect(item.soldFoilQuantity == 1)
        #expect(item.lastSoldPriceUSD == 30.0)
    }

    @Test("recordSale clamps to forSale subset (can't sell more than listed)")
    func recordSaleClamps() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 4, foilQuantity: 2)
        try repo.markForSale(item, nonfoilQuantity: 1, foilQuantity: 1)
        // User claims to have sold 5 foils — but only 1 was listed.
        try repo.recordSale(item, isFoil: true, quantity: 5)
        #expect(item.soldFoilQuantity == 1)
        #expect(item.foilQuantity == 1)        // 2 - 1
    }

    // MARK: - Fetchers

    @Test("fetchForSale returns only items with listed copies, sorted newest first")
    func fetchForSaleSorting() throws {
        let repo = Self.makeRepo()
        let a = try repo.addToCollection(card: Self.makeCard(name: "A"), quantity: 1)
        let b = try repo.addToCollection(card: Self.makeCard(name: "B", collector: "2"), quantity: 1)
        let c = try repo.addToCollection(card: Self.makeCard(name: "C", collector: "3"), quantity: 1)

        // List A first, B second, leave C unlisted.
        try repo.markForSale(a, nonfoilQuantity: 1, foilQuantity: 0)
        try repo.markForSale(b, nonfoilQuantity: 1, foilQuantity: 0)

        let listed = try repo.fetchForSale()
        #expect(listed.count == 2)
        // Newest-first: B was listed second so it comes first.
        #expect(listed[0].cardName == "B")
        #expect(listed[1].cardName == "A")
        #expect(!listed.contains { $0.cardName == "C" })
    }

    // MARK: - Foil-quantity invariant (regression for the batch-scan bug
    // that left foil-only adds with quantity=0, foilQuantity=1)

    @Test("addToCollection preserves the foilQuantity ≤ quantity invariant")
    func addToCollectionFoilInvariant() throws {
        let repo = Self.makeRepo()
        // Simulate the corrected batch-scan call: total=1, all foil.
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 1, foilQuantity: 1)
        #expect(item.quantity == 1)
        #expect(item.foilQuantity == 1)
        #expect(item.foilQuantity <= item.quantity)
        // Snapshot price = foil price for a pure-foil add.
        #expect(item.priceAtAddUSD == 30.45)
    }

    @Test("Repair migration fixes existing rows where foilQuantity > quantity")
    func repairMigrationBackfills() throws {
        // Build a fresh container, manually create a broken row, then
        // re-instantiate the repo to trigger the repair.
        let schema = Schema([
            CardRecord.self, DeckList.self, PurchaseItem.self,
            Order.self, CollectionItem.self, CardAnalysis.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = ModelContext(container)
        let broken = CollectionItem(
            cardName: "Spellstutter Sprite", setCode: "f11", setName: "FNM Promos",
            collectorNumber: "2", scryfallID: "broken-row",
            quantity: 0, foilQuantity: 1
        )
        ctx.insert(broken)
        try ctx.save()

        // Re-init repo — repair runs in init.
        _ = DeckListRepository(modelContainer: container)

        // The same item should now have quantity == foilQuantity == 1.
        let descriptor = FetchDescriptor<CollectionItem>(
            predicate: #Predicate<CollectionItem> { $0.scryfallID == "broken-row" }
        )
        let after = try ModelContext(container).fetch(descriptor).first
        #expect(after?.quantity == 1)
        #expect(after?.foilQuantity == 1)
    }

    @Test("fetchSoldHistory returns items with any sold copies, even when collection is empty")
    func fetchSoldHistoryPreservesEmptyItems() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 1, foilQuantity: 1)
        try repo.markForSale(item, nonfoilQuantity: 0, foilQuantity: 1)
        try repo.recordSale(item, isFoil: true, quantity: 1, soldPriceUSD: 30.0)

        // Even though item.quantity is now 0, the row sticks around.
        let history = try repo.fetchSoldHistory()
        #expect(history.count == 1)
        #expect(history[0].soldFoilQuantity == 1)
    }

    // MARK: - undoSale

    @Test("undoSale of a single foil restores quantity, decrements ledger, clears stamps")
    func undoSaleSingleFoilFullReverse() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 1, foilQuantity: 1)
        try repo.markForSale(item, nonfoilQuantity: 0, foilQuantity: 1, askingPriceFoilUSD: 32.0)
        try repo.recordSale(item, isFoil: true, quantity: 1, soldPriceUSD: 30.0)
        // After the sale: empty collection + 1 sold ledger entry.
        #expect(item.quantity == 0)
        #expect(item.soldFoilQuantity == 1)

        try repo.undoSale(item, isFoil: true, quantity: 1, relist: false)

        #expect(item.foilQuantity == 1)
        #expect(item.quantity == 1)
        #expect(item.soldFoilQuantity == 0)
        #expect(item.soldQuantity == 0)
        // No sales remaining → stamps cleared so the Sold tab drops the row.
        #expect(item.lastSoldAt == nil)
        #expect(item.lastSoldPriceUSD == nil)
        // relist=false: copy returns to collection but is NOT re-listed.
        #expect(item.forSaleFoilQuantity == 0)
    }

    @Test("undoSale with relist=true puts copies back on the Listed tab")
    func undoSaleRelistsWhenRequested() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 1, foilQuantity: 1)
        try repo.markForSale(item, nonfoilQuantity: 0, foilQuantity: 1, askingPriceFoilUSD: 32.0)
        try repo.recordSale(item, isFoil: true, quantity: 1, soldPriceUSD: 30.0)

        try repo.undoSale(item, isFoil: true, quantity: 1, relist: true)

        #expect(item.foilQuantity == 1)
        #expect(item.forSaleFoilQuantity == 1)
        #expect(item.listedAt != nil)
    }

    @Test("undoSale of one copy from a multi-copy sale leaves the rest sold")
    func undoSalePartialReverse() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 4, foilQuantity: 0)
        try repo.markForSale(item, nonfoilQuantity: 4, foilQuantity: 0, askingPriceUSD: 6.0)
        // Sold 3 copies, then realize one buyer flaked.
        try repo.recordSale(item, isFoil: false, quantity: 3, soldPriceUSD: 6.0)
        #expect(item.quantity == 1)
        #expect(item.soldNonfoilQuantity == 3)

        try repo.undoSale(item, isFoil: false, quantity: 1, relist: false)

        #expect(item.quantity == 2)
        #expect(item.soldNonfoilQuantity == 2)
        // 2 copies still sold → stamps remain.
        #expect(item.lastSoldAt != nil)
        #expect(item.lastSoldPriceUSD == 6.0)
    }

    @Test("undoSale on the foil leg does not touch the nonfoil ledger")
    func undoSaleOnlyAffectsRequestedFinish() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 4, foilQuantity: 2)
        try repo.markForSale(item, nonfoilQuantity: 2, foilQuantity: 2)
        try repo.recordSale(item, isFoil: false, quantity: 1, soldPriceUSD: 6.0)
        try repo.recordSale(item, isFoil: true, quantity: 1, soldPriceUSD: 30.0)
        #expect(item.soldNonfoilQuantity == 1)
        #expect(item.soldFoilQuantity == 1)

        try repo.undoSale(item, isFoil: true, quantity: 1, relist: false)

        #expect(item.soldFoilQuantity == 0)
        #expect(item.soldNonfoilQuantity == 1)        // untouched
        #expect(item.foilQuantity == 2)               // restored
        // Started at 4, both finishes sold once → 2; undoing only the
        // foil leg restores 1 → 3. Nonfoil ledger is still 1 sold.
        #expect(item.quantity == 3)
    }

    @Test("undoSale clamps when caller asks for more than was sold")
    func undoSaleClampsToLedger() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 4, foilQuantity: 0)
        try repo.markForSale(item, nonfoilQuantity: 4, foilQuantity: 0)
        try repo.recordSale(item, isFoil: false, quantity: 2, soldPriceUSD: 6.0)
        // Caller tries to undo 5 copies — only 2 are recorded sold.
        try repo.undoSale(item, isFoil: false, quantity: 5, relist: false)

        #expect(item.soldNonfoilQuantity == 0)
        #expect(item.quantity == 4)                   // 2 remaining + 2 restored
    }

    @Test("undoSale of zero quantity is a no-op")
    func undoSaleZeroIsNoOp() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 1, foilQuantity: 0)
        try repo.markForSale(item, nonfoilQuantity: 1, foilQuantity: 0)
        try repo.recordSale(item, isFoil: false, quantity: 1, soldPriceUSD: 6.0)

        try repo.undoSale(item, isFoil: false, quantity: 0, relist: false)

        #expect(item.quantity == 0)
        #expect(item.soldNonfoilQuantity == 1)
        #expect(item.lastSoldPriceUSD == 6.0)
    }

    @Test("undoSale on a finish with no sold copies is a no-op (caller picked wrong finish)")
    func undoSaleWrongFinishIsNoOp() throws {
        let repo = Self.makeRepo()
        let item = try repo.addToCollection(card: Self.makeCard(), quantity: 1, foilQuantity: 0)
        try repo.markForSale(item, nonfoilQuantity: 1, foilQuantity: 0)
        try repo.recordSale(item, isFoil: false, quantity: 1, soldPriceUSD: 6.0)

        // No foil sales exist — nothing should change.
        try repo.undoSale(item, isFoil: true, quantity: 1, relist: false)

        #expect(item.soldFoilQuantity == 0)
        #expect(item.soldNonfoilQuantity == 1)
        #expect(item.quantity == 0)
        #expect(item.lastSoldAt != nil)
    }
}
