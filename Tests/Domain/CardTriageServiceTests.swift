import Testing
import Foundation
@testable import MTGCardScanner

@Suite("Card Triage Service")
struct CardTriageServiceTests {

    // MARK: - Helpers

    private func makeCard(
        name: String = "Test Card",
        set: String = "tmp",
        usd: String? = nil,
        usdFoil: String? = nil,
        legalities: [String: LegalityStatus] = [:],
        finishes: [String] = ["nonfoil"]
    ) -> Card {
        CardTests.makeCard(
            name: name,
            set: SetInfo(code: set, name: set.uppercased(), setType: "expansion", iconSVGURI: nil, releasedAt: "1997-10-14"),
            prices: CardPrices(usd: usd, usdFoil: usdFoil, eur: nil, eurFoil: nil, tix: nil, previousUsd: nil),
            legalities: FormatLegality(legalities),
            finishes: finishes
        )
    }

    // MARK: - Tier S — Reserved List

    @Test("Reserved List card lands in Tier S regardless of price")
    func reservedListCardIsTierS() {
        // "Bayou" is on the Reserved List.
        let card = makeCard(name: "Bayou", set: "lea", usd: "1500.00")
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .s)
        #expect(rating.isReservedList == true)
    }

    @Test("Reserved List card with sub-$5 price still Tier S")
    func reservedListCheapCardIsStillTierS() {
        // Avenging Angel is Reserved List but trades at ~$1.80.
        let card = makeCard(name: "Avenging Angel", set: "tmp", usd: "1.80")
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .s)
        #expect(rating.isReservedList == true)
    }

    // MARK: - Tier S — staples

    @Test("Modern staple lands in Tier S")
    func modernStapleIsTierS() {
        let card = makeCard(
            name: "Lightning Bolt",
            set: "lea",
            usd: "0.50",
            legalities: ["modern": .legal]
        )
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .s)
        #expect(rating.staplesFormats.contains("modern"))
    }

    @Test("Multi-format staple records every format hit")
    func multiFormatStaple() {
        // Counterspell is a curated staple in Modern, Pauper, and Premodern.
        let card = makeCard(
            name: "Counterspell",
            set: "tmp",
            usd: "3.43",
            legalities: ["modern": .legal, "legacy": .legal, "pauper": .legal]
        )
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .s)
        #expect(rating.staplesFormats.contains("modern"))
        #expect(rating.staplesFormats.contains("pauper"))
        #expect(rating.staplesFormats.contains("premodern"))
    }

    // MARK: - Tier S — price floor

    @Test("$20 price floor pushes to Tier S")
    func priceFloorTierS() {
        let card = makeCard(name: "Random Big Card", set: "tmp", usd: "25.00")
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .s)
        #expect(rating.unitPriceUSD == 25.00)
    }

    @Test("$19.99 stays in Tier A — strictly below the floor")
    func justBelowSFloor() {
        let card = makeCard(
            name: "Random Mid Card",
            set: "tmp",
            usd: "19.99",
            legalities: ["legacy": .legal]
        )
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .a)
    }

    // MARK: - Tier A

    @Test("$5 unconditional A floor")
    func priceFloorTierA() {
        let card = makeCard(name: "Mid Card", set: "tmp", usd: "5.00")
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .a)
    }

    @Test("$1.50 + legal qualifies for Tier A")
    func legalAndPriceTierA() {
        let card = makeCard(
            name: "Cheap Legal Card",
            set: "tmp",
            usd: "1.50",
            legalities: ["legacy": .legal]
        )
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .a)
    }

    @Test("$1.49 legal card falls to Tier B")
    func justBelowAFloor() {
        let card = makeCard(
            name: "Cheap Legal Card",
            set: "tmp",
            usd: "1.49",
            legalities: ["legacy": .legal]
        )
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .b)
    }

    // MARK: - Tier B / C

    @Test("$0.50 legal card is Tier B")
    func tierBHit() {
        let card = makeCard(
            name: "Cheap Legal",
            set: "tmp",
            usd: "0.50",
            legalities: ["legacy": .legal]
        )
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .b)
    }

    @Test("$0.50 banned-everywhere card is Tier C")
    func bannedEverywhereIsBulk() {
        let card = makeCard(
            name: "Cheap Banned",
            set: "tmp",
            usd: "0.50",
            legalities: ["modern": .banned, "legacy": .banned, "vintage": .banned]
        )
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .c)
    }

    @Test("No price + no list hits is Tier C")
    func nilPriceIsBulk() {
        let card = makeCard(name: "Unknown", set: "tmp")
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .c)
        #expect(rating.unitPriceUSD == nil)
    }

    // MARK: - Foil-only price logic

    @Test("Foil-only card uses usd_foil for tier math")
    func foilOnlyUsesFoilPrice() {
        // FNM Spellstutter Sprite — foil-only; nonfoil USD missing,
        // foil USD $30. Should land in Tier S off the foil price alone.
        let card = makeCard(
            name: "Spellstutter Sprite",
            set: "f11",
            usd: nil,
            usdFoil: "30.45",
            finishes: ["foil"]
        )
        let rating = CardTriageService.rate(card)
        #expect(rating.tier == .s)
        #expect(rating.unitPriceUSD == 30.45)
    }

    @Test("Non-foil-only card prefers nonfoil price")
    func nonFoilCardPrefersNonfoil() {
        let card = makeCard(
            name: "Random",
            set: "lrw",
            usd: "5.50",
            usdFoil: "25.00",
            finishes: ["nonfoil", "foil"]
        )
        let rating = CardTriageService.rate(card)
        #expect(rating.unitPriceUSD == 5.50)
    }

    // MARK: - Basic land filtering

    @Test("Basic land does not pick up Classic Decks tag")
    func basicLandNotInClassic() {
        let card = makeCard(name: "Forest", set: "tmp", usd: "1.12")
        let rating = CardTriageService.rate(card)
        #expect(rating.lists.contains("Classic") == false)
        #expect(rating.lists.contains("InQuest") == false)
    }

    @Test("Basic land does not pick up InQuest tag from decklist filler")
    func basicLandNotInInQuest() {
        let card = makeCard(name: "Mountain", set: "ice", usd: "1.35")
        let rating = CardTriageService.rate(card)
        #expect(rating.lists.contains("InQuest") == false)
    }

    // MARK: - Set-gated annotation lists

    @Test("Forest from Tempest does NOT match Collectible Lands")
    func forestNotInCollectibleLandsIfWrongSet() {
        // Collectible Lands matches "Forest" only when the printing's
        // set code is one of the curated premium sets (pgru, pelp, etc.).
        let card = makeCard(name: "Forest", set: "tmp", usd: "1.12")
        let rating = CardTriageService.rate(card)
        #expect(rating.lists.contains("Collectible Lands") == false)
    }

    @Test("Plains from Guru set IS in Collectible Lands")
    func plainsFromGuruIsCollectible() {
        let card = makeCard(name: "Plains", set: "pgru", usd: "1200.00")
        let rating = CardTriageService.rate(card)
        #expect(rating.lists.contains("Collectible Lands") == true)
        // Also Tier S because >= $20.
        #expect(rating.tier == .s)
    }

    // MARK: - Tier ordering sanity

    @Test("Tier sortRank orders S < A < B < C")
    func tierOrdering() {
        let order = TriageRating.Tier.allCases.sorted { $0.sortRank < $1.sortRank }
        #expect(order == [.s, .a, .b, .c])
    }
}
