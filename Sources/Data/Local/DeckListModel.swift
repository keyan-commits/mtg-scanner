import Foundation
import SwiftData

// MARK: - Purchase Status

enum PurchaseStatus: String, Codable, CaseIterable, Sendable {
    case needed
    case ordered
    case arrived

    var displayName: String {
        switch self {
        case .needed: return "Needed"
        case .ordered: return "Ordered"
        case .arrived: return "Arrived"
        }
    }
}

// MARK: - DeckList SwiftData Model

@Model
final class DeckList {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String
    var format: String? // "Modern", "Legacy", "Premodern", etc.
    var createdAt: Date
    /// User-chosen icon override. When set, the signature card resolver
    /// returns the matching item directly instead of running the
    /// archetype/heuristic algorithm. Stores `Card.scryfallID` so we can
    /// look up the exact printing.
    var customSignatureScryfallID: String?
    var referenceURL: String?
    /// Human-readable source description (e.g. "InQuest Magazine Issue #1").
    /// Replaces the old "source:" prefix hack on referenceURL.
    var sourceInfo: String?
    @Relationship(deleteRule: .cascade, inverse: \PurchaseItem.deck)
    var items: [PurchaseItem] = []

    init(name: String, format: String? = nil) {
        self.id = UUID()
        self.name = name
        self.format = format
        self.createdAt = Date()
    }
}

// MARK: - Order SwiftData Model

/// A bulk purchase from a single store. One Order owns many PurchaseItems.
/// Captures the buyer-facing currency (which may differ from the store's
/// native currency, e.g. a middle man billing in PHP for a Hareruya JPY order).
@Model
final class Order {
    @Attribute(.unique) var id: UUID = UUID()
    var store: String
    var orderedAt: Date
    var eta: Date?
    var purchaseURL: String?
    var notes: String?
    /// ISO 4217 currency code that `PurchaseItem.pricePaid` is denominated in
    /// for the items linked to this order. e.g. "USD", "PHP", "JPY", "EUR".
    var currency: String
    /// Optional explicit total (e.g. when shipping/tax means it differs from
    /// the sum of per-item prices). Captured verbatim from the seller.
    var totalDue: Double?

    @Relationship(deleteRule: .nullify, inverse: \PurchaseItem.order)
    var items: [PurchaseItem] = []

    init(
        store: String,
        orderedAt: Date = Date(),
        eta: Date? = nil,
        purchaseURL: String? = nil,
        notes: String? = nil,
        currency: String = "USD",
        totalDue: Double? = nil
    ) {
        self.id = UUID()
        self.store = store
        self.orderedAt = orderedAt
        self.eta = eta
        self.purchaseURL = purchaseURL
        self.notes = notes
        self.currency = currency
        self.totalDue = totalDue
    }
}

// MARK: - Deck Signature Card

extension DeckList {
    /// The "signature" card for visual representation. Picked by:
    ///   1. **Archetype-aware**: if the deck matches one of the curated
    ///      `ClassicArchetypes` at ≥50%, score each shared card by
    ///      `canonicalQty * 1000 + 500*nameOverlapWithArchetypeName +
    ///      500*nameOverlapWithDeckTitle`. The card with the highest
    ///      score is the canonical / iconic one.
    ///   2. **Heuristic fallback** (deck doesn't match any archetype):
    ///      quantity desc, then deck-title name overlap, then alphabetical.
    /// Basic lands are excluded. Returns nil for decks with only basics
    /// or no cards.
    var signatureCard: PurchaseItem? {
        // 0. Manual override wins. If the user picked a specific card via
        //    "Choose icon", honor it as long as the matching item still
        //    exists in the deck. Falls through to algorithmic picks if the
        //    override has been deleted from the deck.
        if let customID = customSignatureScryfallID,
           let custom = items.first(where: { $0.scryfallID == customID }) {
            return custom
        }

        let basics: Set<String> = ["plains", "island", "swamp", "mountain", "forest", "wastes"]
        // Build user's lowercased-name → item index for fast joins.
        var userItems: [String: PurchaseItem] = [:]
        for item in items {
            let key = item.cardName.lowercased()
            if basics.contains(key) { continue }
            if userItems[key] == nil {
                userItems[key] = item
            }
        }
        guard !userItems.isEmpty else { return nil }

        // Tokenize deck title once (skip short connectives like "of"/"the").
        let deckTitleWords = significantWords(in: name)

        // 1. Archetype-aware path
        let allNames = items.map { $0.cardName }
        if let match = ArchetypeMatcher.bestMatch(for: allNames, minThreshold: 0.5) {
            let archetypeWords = significantWords(in: match.archetype.name)
            // Score every canonical card the user actually has.
            var best: (item: PurchaseItem, score: Int, name: String)?
            for (canonicalName, canonQty) in match.archetype.mainboard {
                let key = canonicalName.lowercased()
                if basics.contains(key) { continue }
                guard let userItem = userItems[key] else { continue }
                let lowerCard = canonicalName.lowercased()
                var score = canonQty * 1000
                if archetypeWords.contains(where: { lowerCard.contains($0) }) {
                    score += 500
                }
                if deckTitleWords.contains(where: { lowerCard.contains($0) }) {
                    score += 500
                }
                if best == nil
                    || score > best!.score
                    || (score == best!.score && canonicalName < best!.name)
                {
                    best = (item: userItem, score: score, name: canonicalName)
                }
            }
            if let best { return best.item }
        }

        // 2. Heuristic fallback
        var counts: [String: (item: PurchaseItem, count: Int)] = [:]
        for item in items {
            let key = item.cardName.lowercased()
            if basics.contains(key) { continue }
            if var entry = counts[key] {
                entry.count += 1
                counts[key] = entry
            } else {
                counts[key] = (item: item, count: 1)
            }
        }
        return counts.values
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                let lowerA = a.item.cardName.lowercased()
                let lowerB = b.item.cardName.lowercased()
                let am = deckTitleWords.contains(where: { lowerA.contains($0) }) ? 1 : 0
                let bm = deckTitleWords.contains(where: { lowerB.contains($0) }) ? 1 : 0
                if am != bm { return am > bm }
                return a.item.cardName < b.item.cardName
            }
            .first?.item
    }

    /// Extract significant lowercase words from a title — drops short
    /// connectives ("of", "the", "and") that would otherwise create
    /// false-positive matches.
    private func significantWords(in title: String) -> [String] {
        title.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 4 }
    }
}

// MARK: - PurchaseItem SwiftData Model

@Model
final class PurchaseItem {
    @Attribute(.unique) var id: UUID = UUID()
    // Card identity (snapshot — Scryfall printings can change)
    var cardName: String
    var setCode: String
    var setName: String
    var collectorNumber: String
    var scryfallID: String
    var manaCost: String?
    var typeLine: String?

    /// "mainboard" or "sideboard". Defaults to "mainboard" so existing
    /// items migrate cleanly (SwiftData adds new default properties
    /// without an explicit migration).
    var zone: String = "mainboard"

    /// Whether this copy is foil. Affects which price (usd vs usdFoil)
    /// is used for valuation. Defaults to false for existing items.
    var isFoil: Bool = false

    // Quantity & status
    var quantity: Int
    var statusRaw: String // PurchaseStatus.rawValue
    var addedAt: Date

    // Purchase tracking (Phase 2 — all optional)
    var store: String?         // "TCGPlayer", "CardKingdom", etc.
    var purchaseURL: String?   // Order confirmation URL
    var pricePaid: Double?     // What you paid (in the currency below)
    /// ISO 4217 currency code for `pricePaid`. Nil = USD (legacy default).
    var currency: String?
    var notes: String?         // Free-form
    var orderedAt: Date?
    var arrivedAt: Date?

    var deck: DeckList?
    /// Set when this item was bulk-marked as part of an Order.
    var order: Order?

    /// Scryfall USD price snapshot taken when this card was added to the
    /// deck. Used to detect price drops or spikes vs. the live Scryfall
    /// price. Nil for legacy items added before this field existed.
    var priceAtAddUSD: Double?
    /// Date the snapshot was taken (so we can show "added X weeks ago").
    var priceAtAddDate: Date?

    var status: PurchaseStatus {
        get { PurchaseStatus(rawValue: statusRaw) ?? .needed }
        set { statusRaw = newValue.rawValue }
    }

    init(
        cardName: String,
        setCode: String,
        setName: String,
        collectorNumber: String,
        scryfallID: String,
        manaCost: String? = nil,
        typeLine: String? = nil,
        quantity: Int = 1,
        deck: DeckList? = nil
    ) {
        self.id = UUID()
        self.cardName = cardName
        self.setCode = setCode
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.scryfallID = scryfallID
        self.manaCost = manaCost
        self.typeLine = typeLine
        self.quantity = quantity
        self.statusRaw = PurchaseStatus.needed.rawValue
        self.addedAt = Date()
        self.deck = deck
    }
}

// MARK: - Factory from Card

extension PurchaseItem {
    static func from(card: Card, quantity: Int = 1, deck: DeckList? = nil, zone: String = "mainboard", isFoil: Bool = false) -> PurchaseItem {
        let item = PurchaseItem(
            cardName: card.name,
            setCode: card.set.code,
            setName: card.set.name,
            collectorNumber: card.collectorNumber,
            scryfallID: card.scryfallID,
            manaCost: card.manaCost,
            typeLine: card.typeLine,
            quantity: quantity,
            deck: deck
        )
        item.zone = zone
        item.isFoil = isFoil
        // Snapshot the correct price based on foil status.
        let priceStr = isFoil ? (card.prices.usdFoil ?? card.prices.usd) : card.prices.usd
        if let priceStr, let price = Double(priceStr) {
            item.priceAtAddUSD = price
            item.priceAtAddDate = Date()
        }
        return item
    }
}

// MARK: - CollectionItem SwiftData Model

/// One printing the user physically owns. Stored per-printing (set +
/// collector number) so the same card name in two different sets is
/// tracked separately. Used by the Collection feature to know what the
/// user actually has versus what they're shopping for.
@Model
final class CollectionItem {
    @Attribute(.unique) var id: UUID = UUID()
    var cardName: String
    var setCode: String
    var setName: String
    var collectorNumber: String
    var scryfallID: String
    var manaCost: String?
    var typeLine: String?

    /// Total copies owned (regular + foil combined). The whole feature
    /// treats foil as a flavor flag, not a separate inventory bucket.
    var quantity: Int
    /// Subset of `quantity` that are foil. UI is hidden until the user
    /// actually marks something foil.
    var foilQuantity: Int

    var addedAt: Date
    var notes: String?

    /// Scryfall USD price snapshot taken when this item was added to the
    /// collection. Used by the value-change badge in the Collection
    /// screen. Nil for legacy entries.
    var priceAtAddUSD: Double?

    /// What the user actually paid for this card (in their local currency or USD).
    var purchasePrice: Double?
    /// Where the card was purchased (store name, seller, event, etc.).
    var purchaseSource: String?
    /// Current market price per non-foil copy in USD (updated during daily price refresh).
    var currentValueUSD: Double?
    /// Current market price per foil copy in USD (updated during daily price refresh).
    var currentValueFoilUSD: Double?

    init(
        cardName: String,
        setCode: String,
        setName: String,
        collectorNumber: String,
        scryfallID: String,
        manaCost: String? = nil,
        typeLine: String? = nil,
        quantity: Int = 1,
        foilQuantity: Int = 0,
        notes: String? = nil,
        priceAtAddUSD: Double? = nil
    ) {
        self.id = UUID()
        self.cardName = cardName
        self.setCode = setCode
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.scryfallID = scryfallID
        self.manaCost = manaCost
        self.typeLine = typeLine
        self.quantity = quantity
        self.foilQuantity = foilQuantity
        self.addedAt = Date()
        self.notes = notes
        self.priceAtAddUSD = priceAtAddUSD
    }
}

extension CollectionItem {
    static func from(card: Card, quantity: Int = 1, foilQuantity: Int = 0) -> CollectionItem {
        let snapshot = card.prices.usd.flatMap(Double.init)
        return CollectionItem(
            cardName: card.name,
            setCode: card.set.code,
            setName: card.set.name,
            collectorNumber: card.collectorNumber,
            scryfallID: card.scryfallID,
            manaCost: card.manaCost,
            typeLine: card.typeLine,
            quantity: quantity,
            foilQuantity: foilQuantity,
            priceAtAddUSD: snapshot
        )
    }
}

// MARK: - CardAnalysis SwiftData Model

/// A saved card-list analysis. The user pastes a list of cards, the app
/// analyzes which format decks can be built, and the result is persisted
/// so they can come back to it later.
@Model
final class CardAnalysis {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String
    /// The original pasted card list text, preserved for re-analysis.
    var rawCardList: String
    var createdAt: Date
    /// Serialized `[AnalysisFormatResult]` as JSON. Stored as a string so
    /// we can display the results without re-running the analysis.
    var formatResultsJSON: String

    init(title: String, rawCardList: String, formatResultsJSON: String) {
        self.id = UUID()
        self.title = title
        self.rawCardList = rawCardList
        self.createdAt = Date()
        self.formatResultsJSON = formatResultsJSON
    }

    /// Decodes the stored JSON back into analysis results.
    var formatResults: [AnalysisFormatResult] {
        guard let data = formatResultsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([AnalysisFormatResult].self, from: data)) ?? []
    }
}

// MARK: - Serializable Analysis Results

/// A single format's analysis result, stored as part of a `CardAnalysis`.
struct AnalysisFormatResult: Codable, Identifiable {
    var id: String { format }
    let format: String           // DeckFormat rawValue ("modern", "legacy", etc.)
    let displayName: String      // "Modern", "Legacy", etc.
    let archetypeName: String?   // "Infect" or nil
    let referenceURL: String?    // MTGTop8 URL
    let suggestedDeckName: String // "Modern Infect"
    let legalCards: [AnalysisCard]
    let illegalCards: [AnalysisCard]
    let totalLegalQuantity: Int
    let deckSize: Int
    let percentage: Double
}

/// A card entry inside an analysis result.
struct AnalysisCard: Codable, Identifiable {
    var id: String { "\(name)-\(setCode ?? "?")-\(reason ?? "")" }
    let name: String
    let quantity: Int
    let setCode: String?
    let reason: String?  // Why illegal (e.g., "Banned", "Not legal"), nil for legal cards
}

// MARK: - Store URL Detection

extension PurchaseItem {
    /// Auto-detects the store name from a pasted URL.
    static func detectStore(from url: String) -> String? {
        let lower = url.lowercased()
        if lower.contains("tcgplayer.com") { return "TCGPlayer" }
        if lower.contains("cardkingdom.com") { return "CardKingdom" }
        if lower.contains("hareruyamtg.com") || lower.contains("hareruya2.com") { return "Hareruya" }
        if lower.contains("starcitygames.com") { return "Star City Games" }
        if lower.contains("channelfireball.com") { return "ChannelFireball" }
        if lower.contains("ebay.") { return "eBay" }
        if lower.contains("cardmarket.com") { return "Cardmarket" }
        if lower.contains("face2facegames.com") { return "Face to Face Games" }
        if lower.contains("coolstuffinc.com") { return "CoolStuffInc" }
        return nil
    }
}
