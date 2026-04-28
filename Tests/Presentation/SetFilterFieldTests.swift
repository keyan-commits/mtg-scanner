import Testing
import Foundation
@testable import MTGCardScanner

@Suite("Set filter predicate")
struct SetFilterFieldTests {

    private func makeCard(setCode: String, setName: String) -> Card {
        Card(
            scryfallID: "\(setCode)-1",
            name: "Test Card",
            manaCost: nil,
            typeLine: "Instant",
            oracleText: nil,
            set: SetInfo(code: setCode, name: setName, setType: "expansion", iconSVGURI: nil, releasedAt: nil),
            collectorNumber: "1",
            rarity: .common,
            artist: nil,
            releasedAt: nil,
            borderColor: nil,
            frame: nil,
            frameEffects: [],
            illustrationID: nil,
            edhrecRank: nil,
            prices: CardPrices(usd: nil, usdFoil: nil, eur: nil, eurFoil: nil, tix: nil, previousUsd: nil),
            legalities: FormatLegality([:]),
            imageURIs: [:],
            relatedPrintingsURI: nil,
            lang: "en",
            printedName: nil,
            promoTypes: [],
            finishes: ["nonfoil"]
        )
    }

    @Test("Empty query passes all cards through")
    func emptyQueryPasses() {
        let card = makeCard(setCode: "ons", setName: "Onslaught")
        #expect(card.matchesSetFilter("") == true)
    }

    @Test("Whitespace-only query is treated as empty")
    func whitespaceQueryPasses() {
        let card = makeCard(setCode: "ons", setName: "Onslaught")
        #expect(card.matchesSetFilter("   ") == true)
        #expect(card.matchesSetFilter("\t\n") == true)
    }

    @Test("Set name substring match (case insensitive)")
    func setNameSubstring() {
        let card = makeCard(setCode: "ons", setName: "Onslaught")
        #expect(card.matchesSetFilter("ons") == true)
        #expect(card.matchesSetFilter("ONS") == true)
        #expect(card.matchesSetFilter("slaught") == true)
        #expect(card.matchesSetFilter("OnSlAuGhT") == true)
    }

    @Test("Set code substring match (case insensitive)")
    func setCodeSubstring() {
        let card = makeCard(setCode: "DOM", setName: "Dominaria")
        #expect(card.matchesSetFilter("dom") == true)
        #expect(card.matchesSetFilter("DOM") == true)
        #expect(card.matchesSetFilter("Do") == true)
    }

    @Test("Code-only match still passes when name doesn't contain query")
    func codeMatchesWhenNameDoesNot() {
        let card = makeCard(setCode: "PLST", setName: "The List")
        #expect(card.matchesSetFilter("plst") == true)
        // "The List" does not contain "plst"; only the code matches.
    }

    @Test("Name-only match still passes when code doesn't contain query")
    func nameMatchesWhenCodeDoesNot() {
        let card = makeCard(setCode: "EVG", setName: "Duel Decks Anthology: Elves vs. Goblins")
        #expect(card.matchesSetFilter("anthology") == true)
        // EVG doesn't contain "anthology"; only the name matches.
    }

    @Test("Non-matching query rejects card")
    func nonMatchingRejects() {
        let card = makeCard(setCode: "ons", setName: "Onslaught")
        #expect(card.matchesSetFilter("xyz") == false)
        #expect(card.matchesSetFilter("modern") == false)
    }

    @Test("Query with leading/trailing whitespace is trimmed before matching")
    func queryTrimmed() {
        let card = makeCard(setCode: "ons", setName: "Onslaught")
        #expect(card.matchesSetFilter("  ons  ") == true)
        #expect(card.matchesSetFilter("\nslaught\t") == true)
    }
}
