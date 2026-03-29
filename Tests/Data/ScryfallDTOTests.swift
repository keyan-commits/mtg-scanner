import Testing
import Foundation
@testable import MTGCardScanner

@Suite("Scryfall DTO Decoding Tests")
struct ScryfallDTOTests {

    // MARK: - JSON Fixtures

    static let lightningBoltJSON = """
    {
        "id": "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
        "name": "Lightning Bolt",
        "mana_cost": "{R}",
        "type_line": "Instant",
        "oracle_text": "Lightning Bolt deals 3 damage to any target.",
        "set": "2xm",
        "set_name": "Double Masters",
        "set_type": "masters",
        "set_uri": "https://api.scryfall.com/sets/2xm",
        "collector_number": "117",
        "rarity": "uncommon",
        "prices": {
            "usd": "1.50",
            "usd_foil": "3.25",
            "eur": "1.10",
            "eur_foil": "2.80",
            "tix": "0.40"
        },
        "legalities": {
            "standard": "not_legal",
            "modern": "legal",
            "legacy": "legal",
            "vintage": "restricted",
            "commander": "legal",
            "pauper": "legal"
        },
        "image_uris": {
            "small": "https://cards.scryfall.io/small/front/e/2/e2d1f9ad.jpg",
            "normal": "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg",
            "large": "https://cards.scryfall.io/large/front/e/2/e2d1f9ad.jpg",
            "png": "https://cards.scryfall.io/png/front/e/2/e2d1f9ad.png",
            "art_crop": "https://cards.scryfall.io/art_crop/front/e/2/e2d1f9ad.jpg",
            "border_crop": "https://cards.scryfall.io/border_crop/front/e/2/e2d1f9ad.jpg"
        },
        "prints_search_uri": "https://api.scryfall.com/cards/search?order=released&q=oracleid%3Abc9b08eb",
        "border_color": "black",
        "frame": "2015",
        "released_at": "2020-08-07",
        "illustration_id": "bc9b08eb-1234-5678-abcd-ef0123456789"
    }
    """.data(using: .utf8)!

    static let minimalCardJSON = """
    {
        "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "name": "Mox Pearl",
        "type_line": "Artifact",
        "set": "lea",
        "set_name": "Limited Edition Alpha",
        "set_type": "core",
        "set_uri": "https://api.scryfall.com/sets/lea",
        "collector_number": "263",
        "rarity": "rare",
        "prices": {},
        "legalities": {},
        "image_uris": {}
    }
    """.data(using: .utf8)!

    static let searchResultJSON = """
    {
        "object": "list",
        "total_cards": 42,
        "has_more": true,
        "next_page": "https://api.scryfall.com/cards/search?q=lightning&page=2",
        "data": [
            {
                "id": "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
                "name": "Lightning Bolt",
                "type_line": "Instant",
                "set": "2xm",
                "set_name": "Double Masters",
                "set_type": "masters",
                "set_uri": "https://api.scryfall.com/sets/2xm",
                "collector_number": "117",
                "rarity": "uncommon",
                "prices": {},
                "legalities": {},
                "image_uris": {}
            }
        ]
    }
    """.data(using: .utf8)!

    static let searchResultNoMoreJSON = """
    {
        "object": "list",
        "total_cards": 1,
        "has_more": false,
        "data": []
    }
    """.data(using: .utf8)!

    // MARK: - ScryfallCardDTO Decoding

    @Test("Decodes full Lightning Bolt card DTO from JSON")
    func decodesFullCard() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)

        #expect(dto.id == "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43")
        #expect(dto.name == "Lightning Bolt")
        #expect(dto.manaCost == "{R}")
        #expect(dto.typeLine == "Instant")
        #expect(dto.oracleText == "Lightning Bolt deals 3 damage to any target.")
        #expect(dto.set == "2xm")
        #expect(dto.setName == "Double Masters")
        #expect(dto.setType == "masters")
        #expect(dto.setURI == "https://api.scryfall.com/sets/2xm")
        #expect(dto.collectorNumber == "117")
        #expect(dto.rarity == "uncommon")
    }

    @Test("Decodes prices from Lightning Bolt JSON")
    func decodesPrices() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)

        #expect(dto.prices.usd == "1.50")
        #expect(dto.prices.usdFoil == "3.25")
        #expect(dto.prices.eur == "1.10")
        #expect(dto.prices.eurFoil == "2.80")
        #expect(dto.prices.tix == "0.40")
    }

    @Test("Decodes legalities from Lightning Bolt JSON")
    func decodesLegalities() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)

        #expect(dto.legalities["standard"] == "not_legal")
        #expect(dto.legalities["modern"] == "legal")
        #expect(dto.legalities["legacy"] == "legal")
        #expect(dto.legalities["vintage"] == "restricted")
        #expect(dto.legalities["commander"] == "legal")
        #expect(dto.legalities["pauper"] == "legal")
    }

    @Test("Decodes image URIs from Lightning Bolt JSON")
    func decodesImageURIs() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)

        #expect(dto.imageURIs?.count == 6)
        #expect(dto.imageURIs?["small"]?.contains("small") == true)
        #expect(dto.imageURIs?["normal"]?.contains("normal") == true)
        #expect(dto.imageURIs?["large"]?.contains("large") == true)
        #expect(dto.imageURIs?["png"]?.contains("png") == true)
        #expect(dto.imageURIs?["art_crop"]?.contains("art_crop") == true)
        #expect(dto.imageURIs?["border_crop"]?.contains("border_crop") == true)
    }

    @Test("Decodes prints search URI")
    func decodesPrintsSearchURI() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)

        #expect(dto.printsSearchURI == "https://api.scryfall.com/cards/search?order=released&q=oracleid%3Abc9b08eb")
    }

    // MARK: - Optional / Missing Fields

    @Test("Decodes card with missing optional fields")
    func decodesMinimalCard() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.minimalCardJSON)

        #expect(dto.id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(dto.name == "Mox Pearl")
        #expect(dto.manaCost == nil)
        #expect(dto.oracleText == nil)
        #expect(dto.printsSearchURI == nil)
        #expect(dto.typeLine == "Artifact")
        #expect(dto.set == "lea")
        #expect(dto.setName == "Limited Edition Alpha")
        #expect(dto.collectorNumber == "263")
        #expect(dto.rarity == "rare")
    }

    @Test("Minimal card has nil prices when fields are absent")
    func minimalCardNilPrices() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.minimalCardJSON)

        #expect(dto.prices.usd == nil)
        #expect(dto.prices.usdFoil == nil)
        #expect(dto.prices.eur == nil)
        #expect(dto.prices.eurFoil == nil)
        #expect(dto.prices.tix == nil)
    }

    @Test("Minimal card has empty legalities")
    func minimalCardEmptyLegalities() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.minimalCardJSON)

        #expect(dto.legalities.isEmpty)
    }

    // MARK: - Domain Mapping

    @Test("toDomain maps all fields correctly")
    func toDomainMapsAllFields() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)
        let card = dto.toDomain()

        #expect(card.scryfallID == "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43")
        #expect(card.name == "Lightning Bolt")
        #expect(card.manaCost == "{R}")
        #expect(card.typeLine == "Instant")
        #expect(card.oracleText == "Lightning Bolt deals 3 damage to any target.")
        #expect(card.collectorNumber == "117")
        #expect(card.rarity == .uncommon)
    }

    @Test("toDomain maps set info correctly")
    func toDomainMapsSetInfo() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)
        let card = dto.toDomain()

        #expect(card.set.code == "2xm")
        #expect(card.set.name == "Double Masters")
        #expect(card.set.setType == "masters")
    }

    @Test("toDomain maps prices correctly")
    func toDomainMapsPrices() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)
        let card = dto.toDomain()

        #expect(card.prices.usd == "1.50")
        #expect(card.prices.usdFoil == "3.25")
        #expect(card.prices.eur == "1.10")
        #expect(card.prices.eurFoil == "2.80")
        #expect(card.prices.tix == "0.40")
    }

    @Test("toDomain maps legalities correctly")
    func toDomainMapsLegalities() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)
        let card = dto.toDomain()

        #expect(card.legalities.status(for: "modern") == .legal)
        #expect(card.legalities.status(for: "standard") == .notLegal)
        #expect(card.legalities.status(for: "vintage") == .restricted)
    }

    @Test("toDomain maps image URIs correctly")
    func toDomainMapsImageURIs() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)
        let card = dto.toDomain()

        #expect(card.imageURIs.count == 6)
        #expect(card.imageURIs["normal"]?.contains("normal") == true)
    }

    @Test("toDomain maps prints search URI to relatedPrintingsURI")
    func toDomainMapsPrintsSearchURI() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.lightningBoltJSON)
        let card = dto.toDomain()

        #expect(card.relatedPrintingsURI == "https://api.scryfall.com/cards/search?order=released&q=oracleid%3Abc9b08eb")
    }

    @Test("toDomain handles minimal card with missing optionals")
    func toDomainHandlesMinimalCard() throws {
        let decoder = JSONDecoder()

        let dto = try decoder.decode(ScryfallCardDTO.self, from: ScryfallDTOTests.minimalCardJSON)
        let card = dto.toDomain()

        #expect(card.manaCost == nil)
        #expect(card.oracleText == nil)
        #expect(card.relatedPrintingsURI == nil)
        #expect(card.imageURIs.isEmpty)
    }

    // MARK: - ScryfallSearchDTO Decoding

    @Test("Decodes search result with cards and pagination")
    func decodesSearchResult() throws {
        let decoder = JSONDecoder()

        let result = try decoder.decode(ScryfallSearchDTO.self, from: ScryfallDTOTests.searchResultJSON)

        #expect(result.object == "list")
        #expect(result.totalCards == 42)
        #expect(result.hasMore == true)
        #expect(result.nextPage == "https://api.scryfall.com/cards/search?q=lightning&page=2")
        #expect(result.data.count == 1)
        #expect(result.data.first?.name == "Lightning Bolt")
    }

    @Test("Decodes search result with no more pages")
    func decodesSearchResultNoMore() throws {
        let decoder = JSONDecoder()

        let result = try decoder.decode(ScryfallSearchDTO.self, from: ScryfallDTOTests.searchResultNoMoreJSON)

        #expect(result.object == "list")
        #expect(result.totalCards == 1)
        #expect(result.hasMore == false)
        #expect(result.nextPage == nil)
        #expect(result.data.isEmpty)
    }
}
