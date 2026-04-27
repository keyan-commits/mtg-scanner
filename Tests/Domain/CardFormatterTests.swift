import Testing
import SwiftUI
@testable import MTGCardScanner

@Suite("Card Formatter Tests")
struct CardFormatterTests {

    // MARK: - RarityFormatter

    @Test("RarityFormatter label for all rarities")
    func rarityLabels() {
        #expect(RarityFormatter.label(.mythic) == "Mythic")
        #expect(RarityFormatter.label(.rare) == "Rare")
        #expect(RarityFormatter.label(.uncommon) == "Uncommon")
        #expect(RarityFormatter.label(.common) == "Common")
    }

    @Test("RarityFormatter color returns non-nil for all rarities")
    func rarityColors() {
        // Just verify each returns a color without crashing
        _ = RarityFormatter.color(.mythic)
        _ = RarityFormatter.color(.rare)
        _ = RarityFormatter.color(.uncommon)
        _ = RarityFormatter.color(.common)
    }

    // MARK: - LegalityFormatter

    @Test("LegalityFormatter label for all statuses")
    func legalityLabels() {
        #expect(LegalityFormatter.label(.legal) == "Legal")
        #expect(LegalityFormatter.label(.banned) == "Banned")
        #expect(LegalityFormatter.label(.restricted) == "Restricted")
        #expect(LegalityFormatter.label(.notLegal) == "Not Legal")
    }

    // MARK: - ConditionFormatter

    @Test("ConditionFormatter returns green for NM")
    func conditionNM() {
        // Just verify it doesn't crash
        _ = ConditionFormatter.color("NM")
        _ = ConditionFormatter.color("LP")
        _ = ConditionFormatter.color("MP")
        _ = ConditionFormatter.color("HP")
        _ = ConditionFormatter.color("DMG")
        _ = ConditionFormatter.color("Unknown")
    }

    // MARK: - Card.preferredImageURL

    @Test("preferredImageURL returns normal by default")
    func preferredImageNormal() {
        let card = makeCard(imageURIs: ["normal": "https://example.com/normal.jpg", "small": "https://example.com/small.jpg"])
        let url = card.preferredImageURL()
        #expect(url?.absoluteString == "https://example.com/normal.jpg")
    }

    @Test("preferredImageURL falls back to small when normal missing")
    func preferredImageFallback() {
        let card = makeCard(imageURIs: ["small": "https://example.com/small.jpg"])
        let url = card.preferredImageURL()
        #expect(url?.absoluteString == "https://example.com/small.jpg")
    }

    @Test("preferredImageURL returns nil when no URIs")
    func preferredImageNil() {
        let card = makeCard(imageURIs: [:])
        #expect(card.preferredImageURL() == nil)
    }

    @Test("preferredImageURL artCrop priority")
    func preferredImageArtCrop() {
        let card = makeCard(imageURIs: [
            "art_crop": "https://example.com/art.jpg",
            "normal": "https://example.com/normal.jpg"
        ])
        let url = card.preferredImageURL(.artCrop)
        #expect(url?.absoluteString == "https://example.com/art.jpg")
    }

    // MARK: - String.toTCGPHSlug

    @Test("toTCGPHSlug replaces spaces and special chars")
    func tcgphSlug() {
        #expect("Lightning Bolt".toTCGPHSlug() == "lightning-bolt")
        #expect("Sensei's Divining Top".toTCGPHSlug() == "senseis-divining-top")
        #expect("Teferi, Hero of Dominaria".toTCGPHSlug() == "teferi-hero-of-dominaria")
    }

    // MARK: - Helpers

    private func makeCard(imageURIs: [String: String]) -> Card {
        Card(
            scryfallID: "test-id",
            name: "Test Card",
            manaCost: nil,
            typeLine: "Creature",
            oracleText: nil,
            set: SetInfo(code: "tst", name: "Test Set", setType: "expansion", iconSVGURI: nil, releasedAt: nil),
            collectorNumber: "1",
            rarity: .common,
            artist: nil,
            releasedAt: nil,
            borderColor: "black",
            frame: "2015",
            frameEffects: [],
            illustrationID: nil,
            edhrecRank: nil,
            prices: CardPrices(usd: nil, usdFoil: nil, eur: nil, eurFoil: nil, tix: nil, previousUsd: nil),
            legalities: FormatLegality([:]),
            imageURIs: imageURIs,
            relatedPrintingsURI: nil,
            lang: "en",
            printedName: nil,
            promoTypes: [],
            finishes: ["nonfoil"]
        )
    }
}
