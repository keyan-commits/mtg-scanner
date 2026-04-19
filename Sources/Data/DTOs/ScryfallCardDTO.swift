import Foundation

// MARK: - Scryfall Card DTO

struct ScryfallCardDTO: Codable, Sendable {
    let id: String
    let name: String
    let manaCost: String?
    let typeLine: String
    let oracleText: String?
    let set: String
    let setName: String
    let setType: String
    let setURI: String
    let collectorNumber: String
    let rarity: String
    let artist: String?
    let borderColor: String?
    let frame: String?
    let releasedAt: String?
    let illustrationID: String?
    let edhrecRank: Int?
    let prices: ScryfallPricesDTO
    let legalities: [String: String]
    let imageURIs: [String: String]?
    let printsSearchURI: String?

    enum CodingKeys: String, CodingKey {
        case id, name, rarity, artist, prices, legalities, set, frame
        case manaCost = "mana_cost"
        case typeLine = "type_line"
        case oracleText = "oracle_text"
        case setName = "set_name"
        case setType = "set_type"
        case setURI = "set_uri"
        case collectorNumber = "collector_number"
        case imageURIs = "image_uris"
        case printsSearchURI = "prints_search_uri"
        case borderColor = "border_color"
        case releasedAt = "released_at"
        case illustrationID = "illustration_id"
        case edhrecRank = "edhrec_rank"
    }
}

// MARK: - Scryfall Prices DTO

struct ScryfallPricesDTO: Codable, Sendable {
    let usd: String?
    let usdFoil: String?
    let eur: String?
    let eurFoil: String?
    let tix: String?

    enum CodingKeys: String, CodingKey {
        case usd, eur, tix
        case usdFoil = "usd_foil"
        case eurFoil = "eur_foil"
    }
}

// MARK: - Domain Mapping

extension ScryfallCardDTO {
    func toDomain() -> Card {
        let setInfo = SetInfo(
            code: set,
            name: setName,
            setType: setType,
            iconSVGURI: nil,
            releasedAt: nil
        )

        let cardPrices = CardPrices(
            usd: prices.usd,
            usdFoil: prices.usdFoil,
            eur: prices.eur,
            eurFoil: prices.eurFoil,
            tix: prices.tix,
            previousUsd: nil
        )

        let legalityMap: [String: LegalityStatus] = legalities.compactMapValues { rawValue in
            LegalityStatus(rawValue: rawValue)
        }
        let formatLegality = FormatLegality(legalityMap)

        let cardRarity = CardRarity(rawValue: rarity) ?? .common

        return Card(
            scryfallID: id,
            name: name,
            manaCost: manaCost,
            typeLine: typeLine,
            oracleText: oracleText,
            set: setInfo,
            collectorNumber: collectorNumber,
            rarity: cardRarity,
            artist: artist,
            releasedAt: releasedAt,
            borderColor: borderColor,
            frame: frame,
            frameEffects: [],
            illustrationID: illustrationID,
            edhrecRank: edhrecRank,
            prices: cardPrices,
            legalities: formatLegality,
            imageURIs: imageURIs ?? [:],
            relatedPrintingsURI: printsSearchURI
        )
    }
}
