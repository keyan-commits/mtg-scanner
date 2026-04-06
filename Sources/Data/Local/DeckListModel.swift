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
    @Relationship(deleteRule: .cascade, inverse: \PurchaseItem.deck)
    var items: [PurchaseItem] = []

    init(name: String, format: String? = nil) {
        self.id = UUID()
        self.name = name
        self.format = format
        self.createdAt = Date()
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

    // Quantity & status
    var quantity: Int
    var statusRaw: String // PurchaseStatus.rawValue
    var addedAt: Date

    // Purchase tracking (Phase 2 — all optional)
    var store: String?         // "TCGPlayer", "CardKingdom", etc.
    var purchaseURL: String?   // Order confirmation URL
    var pricePaid: Double?     // What you paid (USD)
    var notes: String?         // Free-form
    var orderedAt: Date?
    var arrivedAt: Date?

    var deck: DeckList?

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
        quantity: Int = 1,
        deck: DeckList? = nil
    ) {
        self.id = UUID()
        self.cardName = cardName
        self.setCode = setCode
        self.setName = setName
        self.collectorNumber = collectorNumber
        self.scryfallID = scryfallID
        self.quantity = quantity
        self.statusRaw = PurchaseStatus.needed.rawValue
        self.addedAt = Date()
        self.deck = deck
    }
}

// MARK: - Factory from Card

extension PurchaseItem {
    static func from(card: Card, quantity: Int = 1, deck: DeckList? = nil) -> PurchaseItem {
        PurchaseItem(
            cardName: card.name,
            setCode: card.set.code,
            setName: card.set.name,
            collectorNumber: card.collectorNumber,
            scryfallID: card.scryfallID,
            quantity: quantity,
            deck: deck
        )
    }
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
