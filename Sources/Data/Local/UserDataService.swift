import Foundation
import SwiftData

/// Handles full export and import of user data (decks, collection, orders, analyses).
@MainActor
final class UserDataService {

    private let repository: DeckListRepository

    init(repository: DeckListRepository) {
        self.repository = repository
    }

    // MARK: - Export

    struct ExportData: Codable {
        let version: Int
        let exportedAt: Date
        let decks: [ExportDeck]
        let orders: [ExportOrder]
        let collection: [ExportCollectionItem]
        let analyses: [ExportAnalysis]
        let preferences: ExportPreferences
        let cardInsights: [ExportCardInsight]?
        let deckGuides: [ExportDeckGuide]?
    }

    struct ExportDeck: Codable {
        let id: String
        let name: String
        let format: String?
        let createdAt: Date
        let customSignatureScryfallID: String?
        let referenceURL: String?
        let sourceInfo: String?
        let items: [ExportPurchaseItem]
    }

    struct ExportPurchaseItem: Codable {
        let id: String
        let cardName: String
        let setCode: String
        let setName: String
        let collectorNumber: String
        let scryfallID: String
        let manaCost: String?
        let typeLine: String?
        let zone: String
        let isFoil: Bool
        let quantity: Int
        let status: String
        let addedAt: Date
        let store: String?
        let purchaseURL: String?
        let pricePaid: Double?
        let currency: String?
        let notes: String?
        let orderedAt: Date?
        let arrivedAt: Date?
        let priceAtAddUSD: Double?
        let priceAtAddDate: Date?
        let orderID: String?  // Reference to order by ID
    }

    struct ExportOrder: Codable {
        let id: String
        let store: String
        let orderedAt: Date
        let eta: Date?
        let purchaseURL: String?
        let notes: String?
        let currency: String
        let totalDue: Double?
    }

    struct ExportCollectionItem: Codable {
        let id: String
        let cardName: String
        let setCode: String
        let setName: String
        let collectorNumber: String
        let scryfallID: String
        let manaCost: String?
        let typeLine: String?
        let quantity: Int
        let foilQuantity: Int
        let addedAt: Date
        let notes: String?
        let priceAtAddUSD: Double?
        let purchasePrice: Double?
        let purchaseSource: String?
        let currentValueUSD: Double?
        let currentValueFoilUSD: Double?
    }

    struct ExportAnalysis: Codable {
        let id: String
        let title: String
        let rawCardList: String
        let createdAt: Date
        let formatResultsJSON: String
    }

    struct ExportPreferences: Codable {
        let preferredCurrency: String?
        let printingStrategy: String?
        let appIconRotation: Bool?
        let appIconColor: String?
    }

    struct ExportCardInsight: Codable {
        let scryfallID: String
        let insight: String
        let insightDate: String?
    }

    struct ExportDeckGuide: Codable {
        let key: String   // "deckGuide_<name>_<format>"
        let guide: String
        let date: String?
    }

    /// Exports all user data as a JSON Data blob.
    func exportAll() throws -> Data {
        let decks = (try? repository.fetchAllDecks()) ?? []
        let orders = (try? repository.fetchOrders()) ?? []
        let collection = (try? repository.fetchCollection()) ?? []
        let analyses = (try? repository.fetchAnalyses()) ?? []

        let exportDecks = decks.map { deck -> ExportDeck in
            let items = deck.items.map { item -> ExportPurchaseItem in
                ExportPurchaseItem(
                    id: item.id.uuidString,
                    cardName: item.cardName,
                    setCode: item.setCode,
                    setName: item.setName,
                    collectorNumber: item.collectorNumber,
                    scryfallID: item.scryfallID,
                    manaCost: item.manaCost,
                    typeLine: item.typeLine,
                    zone: item.zone,
                    isFoil: item.isFoil,
                    quantity: item.quantity,
                    status: item.statusRaw,
                    addedAt: item.addedAt,
                    store: item.store,
                    purchaseURL: item.purchaseURL,
                    pricePaid: item.pricePaid,
                    currency: item.currency,
                    notes: item.notes,
                    orderedAt: item.orderedAt,
                    arrivedAt: item.arrivedAt,
                    priceAtAddUSD: item.priceAtAddUSD,
                    priceAtAddDate: item.priceAtAddDate,
                    orderID: item.order?.id.uuidString
                )
            }
            return ExportDeck(
                id: deck.id.uuidString,
                name: deck.name,
                format: deck.format,
                createdAt: deck.createdAt,
                customSignatureScryfallID: deck.customSignatureScryfallID,
                referenceURL: deck.referenceURL,
                sourceInfo: deck.sourceInfo,
                items: items
            )
        }

        let exportOrders = orders.map { order -> ExportOrder in
            ExportOrder(
                id: order.id.uuidString,
                store: order.store,
                orderedAt: order.orderedAt,
                eta: order.eta,
                purchaseURL: order.purchaseURL,
                notes: order.notes,
                currency: order.currency,
                totalDue: order.totalDue
            )
        }

        let exportCollection = collection.map { item -> ExportCollectionItem in
            ExportCollectionItem(
                id: item.id.uuidString,
                cardName: item.cardName,
                setCode: item.setCode,
                setName: item.setName,
                collectorNumber: item.collectorNumber,
                scryfallID: item.scryfallID,
                manaCost: item.manaCost,
                typeLine: item.typeLine,
                quantity: item.quantity,
                foilQuantity: item.foilQuantity,
                addedAt: item.addedAt,
                notes: item.notes,
                priceAtAddUSD: item.priceAtAddUSD,
                purchasePrice: item.purchasePrice,
                purchaseSource: item.purchaseSource,
                currentValueUSD: item.currentValueUSD,
                currentValueFoilUSD: item.currentValueFoilUSD
            )
        }

        let exportAnalyses = analyses.map { analysis -> ExportAnalysis in
            ExportAnalysis(
                id: analysis.id.uuidString,
                title: analysis.title,
                rawCardList: analysis.rawCardList,
                createdAt: analysis.createdAt,
                formatResultsJSON: analysis.formatResultsJSON
            )
        }

        let prefs = ExportPreferences(
            preferredCurrency: UserDefaults.standard.string(forKey: "preferredDisplayCurrency_v1"),
            printingStrategy: UserDefaults.standard.string(forKey: "deckDisplay.printingStrategy"),
            appIconRotation: UserDefaults.standard.object(forKey: "appIcon.rotationEnabled") as? Bool,
            appIconColor: UserDefaults.standard.string(forKey: "appIcon.currentColor")
        )

        // Gather AI card insights from CardRecord DB. This used to fetch
        // every card (~50k Scryfall records) and parse each row's JSON
        // looking for the __insight sentinel — main-thread-blocking for
        // 30-60 sec on device even when the user has zero insights to
        // export. Pre-filter via SwiftData predicate on the substring
        // so only records that actually contain an insight come back.
        let cardInsights: [ExportCardInsight] = {
            let insightKey = "__insight"
            let insightDateKey = "__insight_date"
            let needle = "\"__insight\""    // exact key marker in the JSON blob
            let descriptor = FetchDescriptor<CardRecord>(
                predicate: #Predicate<CardRecord> { record in
                    record.imageURIsJSON.contains(needle)
                }
            )
            guard let candidates = try? repository.context.fetch(descriptor) else { return [] }
            return candidates.compactMap { record in
                guard let jsonData = record.imageURIsJSON.data(using: .utf8),
                      let uris = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
                      let insight = uris[insightKey], !insight.isEmpty else { return nil }
                return ExportCardInsight(
                    scryfallID: record.scryfallID,
                    insight: insight,
                    insightDate: uris[insightDateKey]
                )
            }
        }()

        // Gather AI deck guides from UserDefaults
        let deckGuides: [ExportDeckGuide] = {
            let allDecks = (try? repository.fetchAllDecks()) ?? []
            return allDecks.compactMap { deck in
                let format = deck.format ?? "freeform"
                let key = "deckGuide_\(deck.name)_\(format)"
                let dateKey = "deckGuideDate_\(deck.name)_\(format)"
                guard let guide = UserDefaults.standard.string(forKey: key) else { return nil }
                let date = UserDefaults.standard.string(forKey: dateKey)
                return ExportDeckGuide(key: key, guide: guide, date: date)
            }
        }()

        let export = ExportData(
            version: 1,
            exportedAt: Date(),
            decks: exportDecks,
            orders: exportOrders,
            collection: exportCollection,
            analyses: exportAnalyses,
            preferences: prefs,
            cardInsights: cardInsights.isEmpty ? nil : cardInsights,
            deckGuides: deckGuides.isEmpty ? nil : deckGuides
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    // MARK: - Import

    struct ImportResult {
        var decksImported: Int = 0
        var ordersImported: Int = 0
        var collectionImported: Int = 0
        var analysesImported: Int = 0
        var errors: [String] = []
    }

    /// Imports user data from a JSON blob. Merges with existing data —
    /// skips items that already exist (by ID match).
    func importAll(from data: Data) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let importData = try decoder.decode(ExportData.self, from: data)

        var result = ImportResult()
        let context = repository.context

        // Build lookup of existing IDs to avoid duplicates
        let allDecks: [DeckList] = (try? repository.fetchAllDecks()) ?? []
        let allOrders: [Order] = (try? repository.fetchOrders()) ?? []
        let allCollection: [CollectionItem] = (try? repository.fetchCollection()) ?? []
        let allAnalyses: [CardAnalysis] = (try? repository.fetchAnalyses()) ?? []
        let existingDecks = Set(allDecks.map { $0.id.uuidString })
        let existingOrders = Set(allOrders.map { $0.id.uuidString })
        let existingCollection = Set(allCollection.map { $0.id.uuidString })
        let existingAnalyses = Set(allAnalyses.map { $0.id.uuidString })

        // Import orders first (decks reference them)
        var orderLookup: [String: Order] = [:]
        for eo in importData.orders {
            guard !existingOrders.contains(eo.id) else { continue }
            let order = Order(
                store: eo.store,
                orderedAt: eo.orderedAt,
                eta: eo.eta,
                purchaseURL: eo.purchaseURL,
                notes: eo.notes,
                currency: eo.currency,
                totalDue: eo.totalDue
            )
            if let uuid = UUID(uuidString: eo.id) { order.id = uuid }
            context.insert(order)
            orderLookup[eo.id] = order
            result.ordersImported += 1
        }

        // Import decks with their items
        for ed in importData.decks {
            guard !existingDecks.contains(ed.id) else { continue }
            let deck = DeckList(name: ed.name, format: ed.format)
            if let uuid = UUID(uuidString: ed.id) { deck.id = uuid }
            deck.createdAt = ed.createdAt
            deck.customSignatureScryfallID = ed.customSignatureScryfallID
            deck.referenceURL = ed.referenceURL
            deck.sourceInfo = ed.sourceInfo
            context.insert(deck)

            for ei in ed.items {
                let item = PurchaseItem(
                    cardName: ei.cardName,
                    setCode: ei.setCode,
                    setName: ei.setName,
                    collectorNumber: ei.collectorNumber,
                    scryfallID: ei.scryfallID,
                    manaCost: ei.manaCost,
                    typeLine: ei.typeLine,
                    quantity: ei.quantity,
                    deck: deck
                )
                if let uuid = UUID(uuidString: ei.id) { item.id = uuid }
                item.zone = ei.zone
                item.isFoil = ei.isFoil
                item.statusRaw = ei.status
                item.addedAt = ei.addedAt
                item.store = ei.store
                item.purchaseURL = ei.purchaseURL
                item.pricePaid = ei.pricePaid
                item.currency = ei.currency
                item.notes = ei.notes
                item.orderedAt = ei.orderedAt
                item.arrivedAt = ei.arrivedAt
                item.priceAtAddUSD = ei.priceAtAddUSD
                item.priceAtAddDate = ei.priceAtAddDate
                if let orderID = ei.orderID {
                    item.order = orderLookup[orderID]
                }
                context.insert(item)
            }
            result.decksImported += 1
        }

        // Import collection
        for ec in importData.collection {
            guard !existingCollection.contains(ec.id) else { continue }
            let item = CollectionItem(
                cardName: ec.cardName,
                setCode: ec.setCode,
                setName: ec.setName,
                collectorNumber: ec.collectorNumber,
                scryfallID: ec.scryfallID,
                manaCost: ec.manaCost,
                typeLine: ec.typeLine,
                quantity: ec.quantity,
                foilQuantity: ec.foilQuantity,
                notes: ec.notes,
                priceAtAddUSD: ec.priceAtAddUSD
            )
            if let uuid = UUID(uuidString: ec.id) { item.id = uuid }
            item.addedAt = ec.addedAt
            item.purchasePrice = ec.purchasePrice
            item.purchaseSource = ec.purchaseSource
            item.currentValueUSD = ec.currentValueUSD
            item.currentValueFoilUSD = ec.currentValueFoilUSD
            context.insert(item)
            result.collectionImported += 1
        }

        // Import analyses
        for ea in importData.analyses {
            guard !existingAnalyses.contains(ea.id) else { continue }
            let analysis = CardAnalysis(
                title: ea.title,
                rawCardList: ea.rawCardList,
                formatResultsJSON: ea.formatResultsJSON
            )
            if let uuid = UUID(uuidString: ea.id) { analysis.id = uuid }
            analysis.createdAt = ea.createdAt
            context.insert(analysis)
            result.analysesImported += 1
        }

        try context.save()

        // Import preferences
        if let currency = importData.preferences.preferredCurrency {
            UserDefaults.standard.set(currency, forKey: "preferredDisplayCurrency_v1")
        }
        if let strategy = importData.preferences.printingStrategy {
            UserDefaults.standard.set(strategy, forKey: "deckDisplay.printingStrategy")
        }
        if let rotation = importData.preferences.appIconRotation {
            UserDefaults.standard.set(rotation, forKey: "appIcon.rotationEnabled")
        }
        if let color = importData.preferences.appIconColor {
            UserDefaults.standard.set(color, forKey: "appIcon.currentColor")
        }

        // Import AI card insights
        if let insights = importData.cardInsights, !insights.isEmpty {
            let insightKey = "__insight"
            let insightDateKey = "__insight_date"
            let descriptor = FetchDescriptor<CardRecord>()
            if let allRecords = try? context.fetch(descriptor) {
                let recordMap = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.scryfallID, $0) })
                for ei in insights {
                    guard let record = recordMap[ei.scryfallID] else { continue }
                    // Parse existing imageURIsJSON, inject insight keys
                    guard var uris = (try? JSONSerialization.jsonObject(
                        with: Data(record.imageURIsJSON.utf8)
                    )) as? [String: String] else { continue }
                    uris[insightKey] = ei.insight
                    if let date = ei.insightDate { uris[insightDateKey] = date }
                    if let newJSON = try? JSONSerialization.data(withJSONObject: uris),
                       let jsonStr = String(data: newJSON, encoding: .utf8) {
                        record.imageURIsJSON = jsonStr
                    }
                }
                try? context.save()
            }
        }

        // Import AI deck guides
        if let guides = importData.deckGuides {
            for guide in guides {
                UserDefaults.standard.set(guide.guide, forKey: guide.key)
                let dateKey = guide.key.replacingOccurrences(of: "deckGuide_", with: "deckGuideDate_")
                if let date = guide.date {
                    UserDefaults.standard.set(date, forKey: dateKey)
                }
            }
        }

        return result
    }

    /// Returns a summary of what would be exported (for display in UI).
    func exportSummary() -> (decks: Int, items: Int, orders: Int, collection: Int, analyses: Int) {
        let decks = (try? repository.fetchAllDecks()) ?? []
        let orders = (try? repository.fetchOrders()) ?? []
        let collection = (try? repository.fetchCollection()) ?? []
        let analyses = (try? repository.fetchAnalyses()) ?? []
        let totalItems = decks.reduce(0) { $0 + $1.items.count }
        return (decks: decks.count, items: totalItems, orders: orders.count,
                collection: collection.count, analyses: analyses.count)
    }
}
