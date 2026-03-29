import Foundation

enum CardRarity: String, Sendable, Equatable {
    case common = "common"
    case uncommon = "uncommon"
    case rare = "rare"
    case mythic = "mythic"
}

struct Card: Identifiable, Equatable, Hashable, Sendable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: UUID
    let scryfallID: String
    let name: String
    let manaCost: String?
    let typeLine: String
    let oracleText: String?
    let set: SetInfo
    let collectorNumber: String
    let rarity: CardRarity
    let artist: String?
    let releasedAt: String?
    let borderColor: String?
    let frame: String?
    let illustrationID: String?
    let edhrecRank: Int?
    let prices: CardPrices
    let legalities: FormatLegality
    let imageURIs: [String: String]
    let relatedPrintingsURI: String?
}
