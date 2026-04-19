import Foundation
import SwiftData

// MARK: - CardRecord SwiftData Model

@Model
final class CardRecord {
    @Attribute(.unique) var scryfallID: String
    var name: String
    var manaCost: String?
    var typeLine: String
    var oracleText: String?
    var setCode: String
    var setName: String
    var setType: String
    var collectorNumber: String
    var rarity: String
    var artist: String?
    var releasedAt: String?
    var borderColor: String?
    var frame: String?
    var illustrationID: String?
    var edhrecRank: Int?
    var priceUSD: String?
    var priceUSDFoil: String?
    var priceEUR: String?
    var priceEURFoil: String?
    var priceTix: String?
    /// Previous day's USD price (for computing 24h price change).
    var previousPriceUSD: String?
    var legalitiesJSON: String
    var imageURIsJSON: String
    var printsSearchURI: String?
    /// Whether this card is on the Reserved List (Scryfall `reserved` field).
    var isReserved: Bool = false

    init(
        scryfallID: String,
        name: String,
        manaCost: String?,
        typeLine: String,
        oracleText: String?,
        setCode: String,
        setName: String,
        setType: String,
        collectorNumber: String,
        rarity: String,
        artist: String?,
        releasedAt: String? = nil,
        borderColor: String? = nil,
        frame: String? = nil,
        illustrationID: String? = nil,
        edhrecRank: Int? = nil,
        priceUSD: String?,
        priceUSDFoil: String?,
        priceEUR: String?,
        priceEURFoil: String?,
        priceTix: String?,
        legalitiesJSON: String,
        imageURIsJSON: String,
        printsSearchURI: String?
    ) {
        self.scryfallID = scryfallID
        self.name = name
        self.manaCost = manaCost
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.setCode = setCode
        self.setName = setName
        self.setType = setType
        self.collectorNumber = collectorNumber
        self.rarity = rarity
        self.artist = artist
        self.releasedAt = releasedAt
        self.borderColor = borderColor
        self.frame = frame
        self.illustrationID = illustrationID
        self.edhrecRank = edhrecRank
        self.priceUSD = priceUSD
        self.priceUSDFoil = priceUSDFoil
        self.priceEUR = priceEUR
        self.priceEURFoil = priceEURFoil
        self.priceTix = priceTix
        self.legalitiesJSON = legalitiesJSON
        self.imageURIsJSON = imageURIsJSON
        self.printsSearchURI = printsSearchURI
    }
}

// MARK: - Frame effects encoding
//
// `frame_effects` is needed by `PrintingStrategy` to filter out
// borderless / showcase / extendedart variants whose `borderColor`
// is "black". Adding a new SwiftData field for this would force a
// schema migration that can fail mid-flight on existing installs,
// so we instead piggyback on the existing `imageURIsJSON` blob using
// a sentinel key. Pure encoding trick — no on-disk schema change.

extension CardRecord {
    /// Sentinel key used inside the persisted `imageURIsJSON` dict to
    /// hold a comma-separated list of frame effects.
    static let frameEffectsKey = "__frame_effects"

    /// Encodes frame effects into the imageURIs dict before JSON
    /// serialization. Empty effects are not written.
    static func encodeFrameEffects(_ effects: [String], into imageURIs: inout [String: String]) {
        guard !effects.isEmpty else { return }
        imageURIs[frameEffectsKey] = effects.joined(separator: ",")
    }

    /// Pulls frame effects out of a decoded imageURIs dict, mutating
    /// the dict to remove the sentinel so the rest of the app sees a
    /// clean image-URL map.
    static func extractFrameEffects(from imageURIs: inout [String: String]) -> [String] {
        guard let raw = imageURIs.removeValue(forKey: frameEffectsKey),
              !raw.isEmpty else {
            return []
        }
        return raw.split(separator: ",").map(String.init)
    }
}

// MARK: - Domain Mapping

extension CardRecord {
    func toDomain() -> Card {
        let setInfo = SetInfo(
            code: setCode,
            name: setName,
            setType: setType,
            iconSVGURI: nil,
            releasedAt: nil
        )

        let cardPrices = CardPrices(
            usd: priceUSD,
            usdFoil: priceUSDFoil,
            eur: priceEUR,
            eurFoil: priceEURFoil,
            tix: priceTix,
            previousUsd: previousPriceUSD
        )

        // Decode legalities JSON
        var legalityMap: [String: LegalityStatus] = [:]
        if let data = legalitiesJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            legalityMap = dict.compactMapValues { LegalityStatus(rawValue: $0) }
        }
        let formatLegality = FormatLegality(legalityMap)

        // Decode image URIs JSON. Frame effects are piggybacked under a
        // sentinel key inside this same blob (see `encodeFrameEffects`)
        // so they're extracted out before the dict reaches the UI.
        var imageURIs: [String: String] = [:]
        if let data = imageURIsJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            imageURIs = dict
        }
        let frameEffectsList = Self.extractFrameEffects(from: &imageURIs)

        let cardRarity = CardRarity(rawValue: rarity) ?? .common

        return Card(
            scryfallID: scryfallID,
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
            frameEffects: frameEffectsList,
            illustrationID: illustrationID,
            edhrecRank: edhrecRank,
            prices: cardPrices,
            legalities: formatLegality,
            imageURIs: imageURIs,
            relatedPrintingsURI: printsSearchURI
        )
    }
}

// MARK: - Factory: from ScryfallCardDTO

extension CardRecord {
    static func fromScryfallDTO(_ dto: ScryfallCardDTO) -> CardRecord {
        let legalitiesJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: dto.legalities),
           let jsonString = String(data: data, encoding: .utf8) {
            legalitiesJSON = jsonString
        } else {
            legalitiesJSON = "{}"
        }

        let imageURIsJSON: String
        if let imageURIs = dto.imageURIs,
           let data = try? JSONSerialization.data(withJSONObject: imageURIs),
           let jsonString = String(data: data, encoding: .utf8) {
            imageURIsJSON = jsonString
        } else {
            imageURIsJSON = "{}"
        }

        return CardRecord(
            scryfallID: dto.id,
            name: dto.name,
            manaCost: dto.manaCost,
            typeLine: dto.typeLine,
            oracleText: dto.oracleText,
            setCode: dto.set,
            setName: dto.setName,
            setType: dto.setType,
            collectorNumber: dto.collectorNumber,
            rarity: dto.rarity,
            artist: dto.artist,
            releasedAt: dto.releasedAt,
            borderColor: dto.borderColor,
            frame: dto.frame,
            illustrationID: dto.illustrationID,
            edhrecRank: dto.edhrecRank,
            priceUSD: dto.prices.usd,
            priceUSDFoil: dto.prices.usdFoil,
            priceEUR: dto.prices.eur,
            priceEURFoil: dto.prices.eurFoil,
            priceTix: dto.prices.tix,
            legalitiesJSON: legalitiesJSON,
            imageURIsJSON: imageURIsJSON,
            printsSearchURI: dto.printsSearchURI
        )
    }
}

// MARK: - Factory: from Bulk JSON

extension CardRecord {
    static func fromBulkJSON(_ json: [String: Any]) -> CardRecord? {
        // Required fields
        guard let scryfallID = json["id"] as? String,
              let name = json["name"] as? String,
              let typeLine = json["type_line"] as? String,
              let setCode = json["set"] as? String,
              let setName = json["set_name"] as? String,
              let setType = json["set_type"] as? String,
              let collectorNumber = json["collector_number"] as? String,
              let rarity = json["rarity"] as? String else {
            return nil
        }

        // Optional fields
        let manaCost = json["mana_cost"] as? String
        let oracleText = json["oracle_text"] as? String
        let artist = json["artist"] as? String
        let printsSearchURI = json["prints_search_uri"] as? String
        let releasedAt = json["released_at"] as? String
        let borderColor = json["border_color"] as? String
        let frame = json["frame"] as? String
        let illustrationID = json["illustration_id"] as? String
        let edhrecRank = json["edhrec_rank"] as? Int
        let isReserved = json["reserved"] as? Bool ?? false

        // Prices
        let prices = json["prices"] as? [String: Any] ?? [:]
        let priceUSD = prices["usd"] as? String
        let priceUSDFoil = prices["usd_foil"] as? String
        let priceEUR = prices["eur"] as? String
        let priceEURFoil = prices["eur_foil"] as? String
        let priceTix = prices["tix"] as? String

        // Legalities -> JSON string
        let legalities = json["legalities"] as? [String: String] ?? [:]
        let legalitiesJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: legalities),
           let jsonString = String(data: data, encoding: .utf8) {
            legalitiesJSON = jsonString
        } else {
            legalitiesJSON = "{}"
        }

        // Image URIs -> JSON string.
        //
        // Single-faced cards: `image_uris` lives at the top level.
        // Double-faced / split / adventure / MDFC cards: the top-level
        // `image_uris` field is missing, and each face owns its own
        // `image_uris` under `card_faces[].image_uris`. Without the
        // fallback below, DFCs render as gray placeholders in the grid
        // view because the parser sees an empty top-level dict.
        var imageURIs = json["image_uris"] as? [String: String] ?? [:]
        if imageURIs.isEmpty,
           let cardFaces = json["card_faces"] as? [[String: Any]],
           let frontFaceURIs = cardFaces.first?["image_uris"] as? [String: String] {
            imageURIs = frontFaceURIs
        }

        // Encode frame_effects into the imageURIs blob via a sentinel
        // key. Avoids a SwiftData schema change while still letting
        // PrintingStrategy filter borderless / showcase / extendedart
        // variants whose borderColor is "black".
        let frameEffects = json["frame_effects"] as? [String] ?? []
        Self.encodeFrameEffects(frameEffects, into: &imageURIs)

        let imageURIsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: imageURIs),
           let jsonString = String(data: data, encoding: .utf8) {
            imageURIsJSON = jsonString
        } else {
            imageURIsJSON = "{}"
        }

        let record = CardRecord(
            scryfallID: scryfallID,
            name: name,
            manaCost: manaCost,
            typeLine: typeLine,
            oracleText: oracleText,
            setCode: setCode,
            setName: setName,
            setType: setType,
            collectorNumber: collectorNumber,
            rarity: rarity,
            artist: artist,
            releasedAt: releasedAt,
            borderColor: borderColor,
            frame: frame,
            illustrationID: illustrationID,
            edhrecRank: edhrecRank,
            priceUSD: priceUSD,
            priceUSDFoil: priceUSDFoil,
            priceEUR: priceEUR,
            priceEURFoil: priceEURFoil,
            priceTix: priceTix,
            legalitiesJSON: legalitiesJSON,
            imageURIsJSON: imageURIsJSON,
            printsSearchURI: printsSearchURI
        )
        record.isReserved = isReserved
        return record
    }
}
