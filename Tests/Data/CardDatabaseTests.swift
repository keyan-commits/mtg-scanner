import Testing
import Foundation
@testable import MTGCardScanner

@Suite("CardRecord Tests")
struct CardDatabaseTests {

    // MARK: - Test Fixtures

    static func makeSampleRecord() -> CardRecord {
        let legalities = ["standard": "not_legal", "modern": "legal", "legacy": "legal", "vintage": "restricted"]
        let imageURIs = [
            "small": "https://cards.scryfall.io/small/front/e/2/e2d1f9ad.jpg",
            "normal": "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg",
            "large": "https://cards.scryfall.io/large/front/e/2/e2d1f9ad.jpg"
        ]
        let legalitiesJSON = String(data: try! JSONSerialization.data(withJSONObject: legalities), encoding: .utf8)!
        let imageURIsJSON = String(data: try! JSONSerialization.data(withJSONObject: imageURIs), encoding: .utf8)!

        return CardRecord(
            scryfallID: "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
            name: "Lightning Bolt",
            manaCost: "{R}",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            setCode: "2xm",
            setName: "Double Masters",
            setType: "masters",
            collectorNumber: "117",
            rarity: "uncommon",
            artist: "Christopher Rush",
            priceUSD: "1.50",
            priceUSDFoil: "3.25",
            priceEUR: "1.10",
            priceEURFoil: "2.80",
            priceTix: "0.40",
            legalitiesJSON: legalitiesJSON,
            imageURIsJSON: imageURIsJSON,
            printsSearchURI: "https://api.scryfall.com/cards/search?order=released&q=oracleid%3Abc9b08eb"
        )
    }

    static let sampleBulkJSON: [String: Any] = [
        "id": "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
        "name": "Lightning Bolt",
        "mana_cost": "{R}",
        "type_line": "Instant",
        "oracle_text": "Lightning Bolt deals 3 damage to any target.",
        "set": "2xm",
        "set_name": "Double Masters",
        "set_type": "masters",
        "collector_number": "117",
        "rarity": "uncommon",
        "prices": [
            "usd": "1.50",
            "usd_foil": "3.25",
            "eur": "1.10",
            "eur_foil": "2.80",
            "tix": "0.40"
        ],
        "legalities": [
            "standard": "not_legal",
            "modern": "legal",
            "legacy": "legal"
        ],
        "image_uris": [
            "small": "https://cards.scryfall.io/small/front/e/2/e2d1f9ad.jpg",
            "normal": "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg"
        ],
        "prints_search_uri": "https://api.scryfall.com/cards/search?order=released&q=oracleid%3Abc9b08eb",
        "released_at": "2020-08-07",
        "border_color": "black",
        "frame": "2015",
        "illustration_id": "bc9b08eb-1234-5678-abcd-ef0123456789",
        "edhrec_rank": 158
    ]

    // MARK: - toDomain Tests

    @Test("toDomain maps all fields correctly")
    func toDomainMapsAllFields() {
        let record = CardDatabaseTests.makeSampleRecord()
        let card = record.toDomain()

        #expect(card.scryfallID == "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43")
        #expect(card.name == "Lightning Bolt")
        #expect(card.manaCost == "{R}")
        #expect(card.typeLine == "Instant")
        #expect(card.oracleText == "Lightning Bolt deals 3 damage to any target.")
        #expect(card.collectorNumber == "117")
        #expect(card.rarity == .uncommon)
        #expect(card.set.code == "2xm")
        #expect(card.set.name == "Double Masters")
        #expect(card.set.setType == "masters")
        #expect(card.prices.usd == "1.50")
        #expect(card.prices.usdFoil == "3.25")
        #expect(card.prices.eur == "1.10")
        #expect(card.prices.eurFoil == "2.80")
        #expect(card.prices.tix == "0.40")
        #expect(card.relatedPrintingsURI == "https://api.scryfall.com/cards/search?order=released&q=oracleid%3Abc9b08eb")
    }

    @Test("toDomain decodes legalitiesJSON correctly")
    func toDomainDecodesLegalities() {
        let record = CardDatabaseTests.makeSampleRecord()
        let card = record.toDomain()

        #expect(card.legalities.status(for: "modern") == .legal)
        #expect(card.legalities.status(for: "standard") == .notLegal)
        #expect(card.legalities.status(for: "vintage") == .restricted)
        #expect(card.legalities.status(for: "legacy") == .legal)
    }

    @Test("toDomain decodes imageURIsJSON correctly")
    func toDomainDecodesImageURIs() {
        let record = CardDatabaseTests.makeSampleRecord()
        let card = record.toDomain()

        #expect(card.imageURIs.count == 3)
        #expect(card.imageURIs["small"] == "https://cards.scryfall.io/small/front/e/2/e2d1f9ad.jpg")
        #expect(card.imageURIs["normal"] == "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg")
        #expect(card.imageURIs["large"] == "https://cards.scryfall.io/large/front/e/2/e2d1f9ad.jpg")
    }

    @Test("toDomain handles invalid legalities JSON gracefully")
    func toDomainHandlesInvalidLegalitiesJSON() {
        let record = CardRecord(
            scryfallID: "test-id",
            name: "Test Card",
            manaCost: nil,
            typeLine: "Creature",
            oracleText: nil,
            setCode: "tst",
            setName: "Test Set",
            setType: "core",
            collectorNumber: "1",
            rarity: "common",
            artist: nil,
            priceUSD: nil,
            priceUSDFoil: nil,
            priceEUR: nil,
            priceEURFoil: nil,
            priceTix: nil,
            legalitiesJSON: "not valid json",
            imageURIsJSON: "{}",
            printsSearchURI: nil
        )
        let card = record.toDomain()

        #expect(card.legalities.allFormats.isEmpty)
    }

    @Test("toDomain handles invalid imageURIs JSON gracefully")
    func toDomainHandlesInvalidImageURIsJSON() {
        let record = CardRecord(
            scryfallID: "test-id",
            name: "Test Card",
            manaCost: nil,
            typeLine: "Creature",
            oracleText: nil,
            setCode: "tst",
            setName: "Test Set",
            setType: "core",
            collectorNumber: "1",
            rarity: "common",
            artist: nil,
            priceUSD: nil,
            priceUSDFoil: nil,
            priceEUR: nil,
            priceEURFoil: nil,
            priceTix: nil,
            legalitiesJSON: "{}",
            imageURIsJSON: "not valid json",
            printsSearchURI: nil
        )
        let card = record.toDomain()

        #expect(card.imageURIs.isEmpty)
    }

    // MARK: - fromBulkJSON Tests

    @Test("fromBulkJSON parses a realistic Scryfall bulk JSON dictionary")
    func fromBulkJSONParsesRealisticData() {
        let record = CardRecord.fromBulkJSON(CardDatabaseTests.sampleBulkJSON)

        #expect(record != nil)
        #expect(record?.scryfallID == "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43")
        #expect(record?.name == "Lightning Bolt")
        #expect(record?.manaCost == "{R}")
        #expect(record?.typeLine == "Instant")
        #expect(record?.oracleText == "Lightning Bolt deals 3 damage to any target.")
        #expect(record?.setCode == "2xm")
        #expect(record?.setName == "Double Masters")
        #expect(record?.setType == "masters")
        #expect(record?.collectorNumber == "117")
        #expect(record?.rarity == "uncommon")
        #expect(record?.priceUSD == "1.50")
        #expect(record?.priceUSDFoil == "3.25")
        #expect(record?.priceEUR == "1.10")
        #expect(record?.priceEURFoil == "2.80")
        #expect(record?.priceTix == "0.40")
        #expect(record?.printsSearchURI == "https://api.scryfall.com/cards/search?order=released&q=oracleid%3Abc9b08eb")
    }

    @Test("fromBulkJSON parses legalities into JSON string")
    func fromBulkJSONParsesLegalities() {
        let record = CardRecord.fromBulkJSON(CardDatabaseTests.sampleBulkJSON)

        #expect(record != nil)
        // Verify the JSON string can be deserialized back
        let data = record!.legalitiesJSON.data(using: .utf8)!
        let legalities = try! JSONSerialization.jsonObject(with: data) as! [String: String]
        #expect(legalities["modern"] == "legal")
        #expect(legalities["standard"] == "not_legal")
        #expect(legalities["legacy"] == "legal")
    }

    @Test("fromBulkJSON parses image URIs into JSON string")
    func fromBulkJSONParsesImageURIs() {
        let record = CardRecord.fromBulkJSON(CardDatabaseTests.sampleBulkJSON)

        #expect(record != nil)
        let data = record!.imageURIsJSON.data(using: .utf8)!
        let imageURIs = try! JSONSerialization.jsonObject(with: data) as! [String: String]
        #expect(imageURIs["small"] == "https://cards.scryfall.io/small/front/e/2/e2d1f9ad.jpg")
        #expect(imageURIs["normal"] == "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg")
    }

    @Test("fromBulkJSON returns nil for missing required id field")
    func fromBulkJSONReturnsNilForMissingID() {
        var json = CardDatabaseTests.sampleBulkJSON
        json.removeValue(forKey: "id")
        let record = CardRecord.fromBulkJSON(json)
        #expect(record == nil)
    }

    @Test("fromBulkJSON returns nil for missing required name field")
    func fromBulkJSONReturnsNilForMissingName() {
        var json = CardDatabaseTests.sampleBulkJSON
        json.removeValue(forKey: "name")
        let record = CardRecord.fromBulkJSON(json)
        #expect(record == nil)
    }

    @Test("fromBulkJSON returns nil for missing required type_line field")
    func fromBulkJSONReturnsNilForMissingTypeLine() {
        var json = CardDatabaseTests.sampleBulkJSON
        json.removeValue(forKey: "type_line")
        let record = CardRecord.fromBulkJSON(json)
        #expect(record == nil)
    }

    @Test("fromBulkJSON returns nil for missing required set field")
    func fromBulkJSONReturnsNilForMissingSet() {
        var json = CardDatabaseTests.sampleBulkJSON
        json.removeValue(forKey: "set")
        let record = CardRecord.fromBulkJSON(json)
        #expect(record == nil)
    }

    @Test("fromBulkJSON returns nil for missing required collector_number field")
    func fromBulkJSONReturnsNilForMissingCollectorNumber() {
        var json = CardDatabaseTests.sampleBulkJSON
        json.removeValue(forKey: "collector_number")
        let record = CardRecord.fromBulkJSON(json)
        #expect(record == nil)
    }

    @Test("fromBulkJSON returns nil for missing required rarity field")
    func fromBulkJSONReturnsNilForMissingRarity() {
        var json = CardDatabaseTests.sampleBulkJSON
        json.removeValue(forKey: "rarity")
        let record = CardRecord.fromBulkJSON(json)
        #expect(record == nil)
    }

    @Test("fromBulkJSON handles missing optional fields gracefully")
    func fromBulkJSONHandlesMissingOptionalFields() {
        let minimalJSON: [String: Any] = [
            "id": "test-id-123",
            "name": "Minimal Card",
            "type_line": "Creature",
            "set": "tst",
            "set_name": "Test Set",
            "set_type": "core",
            "collector_number": "1",
            "rarity": "common",
            "legalities": [:] as [String: String],
            "prices": [:] as [String: Any]
        ]

        let record = CardRecord.fromBulkJSON(minimalJSON)

        #expect(record != nil)
        #expect(record?.scryfallID == "test-id-123")
        #expect(record?.name == "Minimal Card")
        #expect(record?.manaCost == nil)
        #expect(record?.oracleText == nil)
        #expect(record?.priceUSD == nil)
        #expect(record?.priceUSDFoil == nil)
        #expect(record?.priceEUR == nil)
        #expect(record?.priceEURFoil == nil)
        #expect(record?.priceTix == nil)
        #expect(record?.printsSearchURI == nil)
    }

    // MARK: - fromScryfallDTO Tests

    @Test("fromScryfallDTO maps DTO fields to CardRecord")
    func fromScryfallDTOMapsFields() {
        let dto = ScryfallCardDTO(
            id: "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
            name: "Lightning Bolt",
            manaCost: "{R}",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            set: "2xm",
            setName: "Double Masters",
            setType: "masters",
            setURI: "https://api.scryfall.com/sets/2xm",
            collectorNumber: "117",
            rarity: "uncommon",
            artist: "Christopher Rush",
            borderColor: "black",
            frame: "2015",
            releasedAt: "2020-08-07",
            illustrationID: nil,
            edhrecRank: 158,
            prices: ScryfallPricesDTO(
                usd: "1.50",
                usdFoil: "3.25",
                eur: "1.10",
                eurFoil: "2.80",
                tix: "0.40"
            ),
            legalities: ["standard": "not_legal", "modern": "legal"],
            imageURIs: ["normal": "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg"],
            printsSearchURI: "https://api.scryfall.com/cards/search?q=oracleid%3Abc9b08eb"
        )

        let record = CardRecord.fromScryfallDTO(dto)

        #expect(record.scryfallID == "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43")
        #expect(record.name == "Lightning Bolt")
        #expect(record.manaCost == "{R}")
        #expect(record.typeLine == "Instant")
        #expect(record.oracleText == "Lightning Bolt deals 3 damage to any target.")
        #expect(record.setCode == "2xm")
        #expect(record.setName == "Double Masters")
        #expect(record.setType == "masters")
        #expect(record.collectorNumber == "117")
        #expect(record.rarity == "uncommon")
        #expect(record.priceUSD == "1.50")
        #expect(record.priceUSDFoil == "3.25")
        #expect(record.priceEUR == "1.10")
        #expect(record.priceEURFoil == "2.80")
        #expect(record.priceTix == "0.40")
        #expect(record.printsSearchURI == "https://api.scryfall.com/cards/search?q=oracleid%3Abc9b08eb")
    }

    @Test("fromScryfallDTO round-trips through toDomain correctly")
    func fromScryfallDTORoundTrips() {
        let dto = ScryfallCardDTO(
            id: "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
            name: "Lightning Bolt",
            manaCost: "{R}",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            set: "2xm",
            setName: "Double Masters",
            setType: "masters",
            setURI: "https://api.scryfall.com/sets/2xm",
            collectorNumber: "117",
            rarity: "uncommon",
            artist: "Christopher Rush",
            borderColor: "black",
            frame: "2015",
            releasedAt: "2020-08-07",
            illustrationID: nil,
            edhrecRank: nil,
            prices: ScryfallPricesDTO(
                usd: "1.50",
                usdFoil: "3.25",
                eur: "1.10",
                eurFoil: "2.80",
                tix: "0.40"
            ),
            legalities: ["standard": "not_legal", "modern": "legal"],
            imageURIs: ["normal": "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg"],
            printsSearchURI: "https://api.scryfall.com/cards/search?q=oracleid%3Abc9b08eb"
        )

        let record = CardRecord.fromScryfallDTO(dto)
        let card = record.toDomain()

        #expect(card.scryfallID == dto.id)
        #expect(card.name == dto.name)
        #expect(card.manaCost == dto.manaCost)
        #expect(card.typeLine == dto.typeLine)
        #expect(card.oracleText == dto.oracleText)
        #expect(card.set.code == dto.set)
        #expect(card.set.name == dto.setName)
        #expect(card.collectorNumber == dto.collectorNumber)
        #expect(card.rarity == .uncommon)
        #expect(card.prices.usd == dto.prices.usd)
        #expect(card.legalities.status(for: "modern") == .legal)
        #expect(card.imageURIs["normal"] == dto.imageURIs?["normal"])
    }
}
