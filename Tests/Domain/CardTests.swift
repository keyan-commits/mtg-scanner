import Testing
import Foundation
@testable import MTGCardScanner

@Suite("Card Entity Tests")
struct CardTests {

    // MARK: - Test Helpers

    static func makeSetInfo(
        code: String = "neo",
        name: String = "Kamigawa: Neon Dynasty",
        setType: String = "expansion",
        iconSVGURI: String? = nil,
        releasedAt: String? = "2022-02-18"
    ) -> SetInfo {
        SetInfo(
            code: code,
            name: name,
            setType: setType,
            iconSVGURI: iconSVGURI,
            releasedAt: releasedAt
        )
    }

    static func makePrices(
        usd: String? = "1.50",
        usdFoil: String? = "3.00",
        eur: String? = "1.20",
        eurFoil: String? = "2.50",
        tix: String? = "0.50"
    ) -> CardPrices {
        CardPrices(
            usd: usd,
            usdFoil: usdFoil,
            eur: eur,
            eurFoil: eurFoil,
            tix: tix
        )
    }

    static func makeCard(
        id: UUID = UUID(),
        scryfallID: String = "abc-123",
        name: String = "Lightning Bolt",
        manaCost: String? = "{R}",
        typeLine: String = "Instant",
        oracleText: String? = "Lightning Bolt deals 3 damage to any target.",
        set: SetInfo? = nil,
        collectorNumber: String = "1",
        rarity: CardRarity = .common,
        artist: String? = nil,
        releasedAt: String? = nil,
        borderColor: String? = nil,
        frame: String? = nil,
        illustrationID: String? = nil,
        prices: CardPrices? = nil,
        legalities: FormatLegality = FormatLegality([:]),
        imageURIs: [String: String] = [:],
        relatedPrintingsURI: String? = nil
    ) -> Card {
        Card(
            id: id,
            scryfallID: scryfallID,
            name: name,
            manaCost: manaCost,
            typeLine: typeLine,
            oracleText: oracleText,
            set: set ?? makeSetInfo(),
            collectorNumber: collectorNumber,
            rarity: rarity,
            artist: artist,
            releasedAt: releasedAt,
            borderColor: borderColor,
            frame: frame,
            illustrationID: illustrationID,
            prices: prices ?? makePrices(),
            legalities: legalities,
            imageURIs: imageURIs,
            relatedPrintingsURI: relatedPrintingsURI
        )
    }

    // MARK: - Initialization

    @Test("Card initializes with all properties")
    func initialization() {
        let id = UUID()
        let setInfo = CardTests.makeSetInfo()
        let prices = CardTests.makePrices()
        let legalities = FormatLegality([
            "standard": .notLegal,
            "modern": .legal,
            "legacy": .legal
        ])

        let card = Card(
            id: id,
            scryfallID: "abc-123",
            name: "Lightning Bolt",
            manaCost: "{R}",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            set: setInfo,
            collectorNumber: "1",
            rarity: .common,
            artist: "Christopher Rush",
            releasedAt: nil,
            borderColor: nil,
            frame: nil,
            illustrationID: nil,
            prices: prices,
            legalities: legalities,
            imageURIs: ["normal": "https://example.com/bolt.jpg"],
            relatedPrintingsURI: "/prints/bolt"
        )

        #expect(card.id == id)
        #expect(card.scryfallID == "abc-123")
        #expect(card.name == "Lightning Bolt")
        #expect(card.manaCost == "{R}")
        #expect(card.typeLine == "Instant")
        #expect(card.oracleText == "Lightning Bolt deals 3 damage to any target.")
        #expect(card.set.code == "neo")
        #expect(card.collectorNumber == "1")
        #expect(card.rarity == .common)
        #expect(card.prices.usd == "1.50")
        #expect(card.imageURIs["normal"] == "https://example.com/bolt.jpg")
        #expect(card.relatedPrintingsURI == "/prints/bolt")
    }

    @Test("Card initializes with nil optional properties")
    func initializationWithNils() {
        let card = CardTests.makeCard(
            manaCost: nil,
            oracleText: nil,
            relatedPrintingsURI: nil
        )

        #expect(card.manaCost == nil)
        #expect(card.oracleText == nil)
        #expect(card.relatedPrintingsURI == nil)
    }

    // MARK: - Equality

    @Test("Cards with same id are equal")
    func equalityById() {
        let id = UUID()
        let card1 = CardTests.makeCard(id: id, name: "Lightning Bolt")
        let card2 = CardTests.makeCard(id: id, name: "Lightning Bolt")

        #expect(card1 == card2)
    }

    @Test("Cards with different ids are not equal")
    func inequalityByDifferentId() {
        let card1 = CardTests.makeCard(id: UUID(), name: "Lightning Bolt")
        let card2 = CardTests.makeCard(id: UUID(), name: "Lightning Bolt")

        #expect(card1 != card2)
    }

    // MARK: - Format Legality

    @Test("Card reports legal in a format")
    func isLegalInFormat() {
        let legalities = FormatLegality([
            "modern": .legal,
            "standard": .notLegal,
            "legacy": .banned,
            "vintage": .restricted
        ])

        #expect(legalities.isLegal(in: "modern") == true)
        #expect(legalities.isLegal(in: "standard") == false)
        #expect(legalities.isLegal(in: "legacy") == false)
        #expect(legalities.isLegal(in: "vintage") == false)
        #expect(legalities.isLegal(in: "unknown") == false)
    }

    @Test("FormatLegality returns correct status for format")
    func formatLegalityStatus() {
        let legalities = FormatLegality([
            "modern": .legal,
            "standard": .notLegal,
            "legacy": .banned,
            "vintage": .restricted
        ])

        #expect(legalities.status(for: "modern") == .legal)
        #expect(legalities.status(for: "standard") == .notLegal)
        #expect(legalities.status(for: "legacy") == .banned)
        #expect(legalities.status(for: "vintage") == .restricted)
        #expect(legalities.status(for: "nonexistent") == nil)
    }

    // MARK: - Price Display

    @Test("Formatted price returns USD when available")
    func formattedPriceWithUSD() {
        let prices = CardTests.makePrices(usd: "1.50", usdFoil: "3.00")
        #expect(prices.formattedPrice == "$1.50")
    }

    @Test("Formatted price falls back to USD foil")
    func formattedPriceFallsBackToFoil() {
        let prices = CardTests.makePrices(usd: nil, usdFoil: "3.00")
        #expect(prices.formattedPrice == "$3.00 (foil)")
    }

    @Test("Formatted price returns nil when no USD prices")
    func formattedPriceReturnsNilWithoutUSD() {
        let prices = CardTests.makePrices(usd: nil, usdFoil: nil, eur: "1.20")
        #expect(prices.formattedPrice == nil)
    }

    @Test("Formatted price returns nil when all prices are nil")
    func formattedPriceReturnsNilForEmptyPrices() {
        let prices = CardPrices(usd: nil, usdFoil: nil, eur: nil, eurFoil: nil, tix: nil)
        #expect(prices.formattedPrice == nil)
    }

    // MARK: - CardRarity

    @Test("CardRarity raw values match Scryfall API strings")
    func cardRarityRawValues() {
        #expect(CardRarity.common.rawValue == "common")
        #expect(CardRarity.uncommon.rawValue == "uncommon")
        #expect(CardRarity.rare.rawValue == "rare")
        #expect(CardRarity.mythic.rawValue == "mythic")
    }

    // MARK: - LegalityStatus

    @Test("LegalityStatus raw values match Scryfall API strings")
    func legalityStatusRawValues() {
        #expect(LegalityStatus.legal.rawValue == "legal")
        #expect(LegalityStatus.notLegal.rawValue == "not_legal")
        #expect(LegalityStatus.banned.rawValue == "banned")
        #expect(LegalityStatus.restricted.rawValue == "restricted")
    }

    @Test("LegalityStatus initializes from raw value")
    func legalityStatusFromRawValue() {
        #expect(LegalityStatus(rawValue: "legal") == .legal)
        #expect(LegalityStatus(rawValue: "not_legal") == .notLegal)
        #expect(LegalityStatus(rawValue: "banned") == .banned)
        #expect(LegalityStatus(rawValue: "restricted") == .restricted)
        #expect(LegalityStatus(rawValue: "invalid") == nil)
    }

    // MARK: - SetInfo

    @Test("SetInfo initializes correctly")
    func setInfoInitialization() {
        let setInfo = SetInfo(
            code: "neo",
            name: "Kamigawa: Neon Dynasty",
            setType: "expansion",
            iconSVGURI: "https://example.com/icon.svg",
            releasedAt: "2022-02-18"
        )

        #expect(setInfo.code == "neo")
        #expect(setInfo.name == "Kamigawa: Neon Dynasty")
        #expect(setInfo.setType == "expansion")
        #expect(setInfo.iconSVGURI == "https://example.com/icon.svg")
        #expect(setInfo.releasedAt == "2022-02-18")
    }

    // MARK: - ScanResult

    @Test("ScanResult initializes correctly")
    func scanResultInitialization() {
        let boundingBox = CGRect(x: 10, y: 20, width: 100, height: 50)
        let result = ScanResult(
            recognizedText: "Lightning Bolt",
            confidence: 0.95,
            boundingBox: boundingBox
        )

        #expect(result.recognizedText == "Lightning Bolt")
        #expect(result.confidence == 0.95)
        #expect(result.boundingBox == boundingBox)
    }
}
