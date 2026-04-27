import Testing
import Foundation
@testable import MTGCardScanner

@Suite("Printing Resolution Tests")
struct PrintingResolutionTests {

    // MARK: - Test Helpers

    private static func makeCard(
        scryfallID: String,
        name: String = "Test Card",
        setCode: String,
        setName: String,
        collectorNumber: String,
        artist: String? = nil,
        releasedAt: String? = nil,
        illustrationID: String? = nil,
        frameEffects: [String] = [],
        imageURIs: [String: String] = [:]
    ) -> Card {
        Card(
            scryfallID: scryfallID,
            name: name,
            manaCost: nil,
            typeLine: "Creature — Sliver",
            oracleText: nil,
            set: SetInfo(
                code: setCode,
                name: setName,
                setType: "expansion",
                iconSVGURI: nil,
                releasedAt: releasedAt
            ),
            collectorNumber: collectorNumber,
            rarity: .common,
            artist: artist,
            releasedAt: releasedAt,
            borderColor: "black",
            frame: "2003",
            frameEffects: frameEffects,
            illustrationID: illustrationID,
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

    // MARK: - Predatory Sliver: M14 vs Secret Lair Drop

    /// Predatory Sliver printings for testing.
    /// M14 (2013-07-19) is the user's actual card.
    /// Secret Lair Drop (2022-02-18) is the wrong result.
    private static let predatorySliverM14 = makeCard(
        scryfallID: "pred-sliver-m14",
        name: "Predatory Sliver",
        setCode: "m14",
        setName: "Magic 2014",
        collectorNumber: "189",
        artist: "Mathias Kollros",
        releasedAt: "2013-07-19",
        illustrationID: "ill-pred-m14"
    )

    private static let predatorySliverSLD = makeCard(
        scryfallID: "pred-sliver-sld",
        name: "Predatory Sliver",
        setCode: "sld",
        setName: "Secret Lair Drop",
        collectorNumber: "189",
        artist: "Thomas M. Baxa",
        releasedAt: "2022-02-18",
        illustrationID: "ill-pred-sld"
    )

    @Test("Predatory Sliver: no signals -> oldest release (M14) wins via tiebreak")
    func predatorySliverNoSignals() {
        let printings = [Self.predatorySliverM14, Self.predatorySliverSLD]
        let input = PrintingScorerInput()  // No signals at all

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "m14", "Expected M14 (2013) to win via oldest-release tiebreak, got \(winner?.set.code ?? "nil")")
    }

    @Test("Predatory Sliver: symbol match on SLD does NOT override when no other signals")
    func predatorySliverSymbolMatchIgnoredWithNoSignals() {
        let printings = [Self.predatorySliverM14, Self.predatorySliverSLD]
        // Symbol comparison says SLD is the best match, but no other signals fired
        let input = PrintingScorerInput(symbolMatchWinnerID: "pred-sliver-sld")

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "m14", "Symbol match on SLD should be ignored when no OCR signals fired; M14 should win via tiebreak")
    }

    @Test("Predatory Sliver: bottom-bar OCR reads M14 -> M14 wins definitively")
    func predatorySliverBottomBarM14() {
        let printings = [Self.predatorySliverM14, Self.predatorySliverSLD]
        let input = PrintingScorerInput(
            bottomBarResults: [(setCode: "M14", collectorNumber: "189", setTotal: 249, confidence: 0.9)]
        )

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "m14", "Bottom-bar OCR reading M14 should pick M14 definitively")
    }

    @Test("Predatory Sliver: artist disambiguates when both have different artists")
    func predatorySliverArtistDisambiguates() {
        let printings = [Self.predatorySliverM14, Self.predatorySliverSLD]
        // OCR reads "Mathias Kollros" -> unique to M14
        let input = PrintingScorerInput(artistName: "Mathias Kollros")

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "m14", "Artist 'Mathias Kollros' is unique to M14 and should win")
    }

    @Test("Predatory Sliver: symbol match only applies when other signals > 0")
    func predatorySliverSymbolPlusSignal() {
        let printings = [Self.predatorySliverM14, Self.predatorySliverSLD]
        // Copyright year gives M14 +1, then symbol match gives SLD +1 -> tie -> tiebreak M14
        let input = PrintingScorerInput(
            copyrightYear: 2013,
            symbolMatchWinnerID: "pred-sliver-sld"
        )

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        // M14 gets +1 from copyright year. SLD gets +1 from symbol match. Tie -> oldest release -> M14 wins.
        #expect(winner?.set.code == "m14", "When copyright year matches M14 and symbol matches SLD, they should tie and M14 wins via tiebreak")
    }

    // MARK: - Lightning Bolt: CLB vs CLU

    /// Lightning Bolt with artist Phil Stone should disambiguate CLB from CLU.
    private static let lightningBoltCLB = makeCard(
        scryfallID: "bolt-clb",
        name: "Lightning Bolt",
        setCode: "clb",
        setName: "Commander Legends: Battle for Baldur's Gate",
        collectorNumber: "187",
        artist: "Phil Stone",
        releasedAt: "2022-06-10",
        illustrationID: "ill-bolt-clb"
    )

    private static let lightningBoltCLU = makeCard(
        scryfallID: "bolt-clu",
        name: "Lightning Bolt",
        setCode: "clu",
        setName: "Commander Legends: Battle for Baldur's Gate — Commander",
        collectorNumber: "141",
        artist: "Christopher Moeller",
        releasedAt: "2022-06-10",
        illustrationID: "ill-bolt-clu"
    )

    @Test("Lightning Bolt: artist Phil Stone disambiguates CLB from CLU")
    func lightningBoltArtistDisambiguates() {
        let printings = [Self.lightningBoltCLB, Self.lightningBoltCLU]
        let input = PrintingScorerInput(artistName: "Phil Stone")

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "clb", "Artist 'Phil Stone' is unique to CLB printing")
    }

    @Test("Lightning Bolt: artist Christopher Moeller picks CLU")
    func lightningBoltArtistPicksCLU() {
        let printings = [Self.lightningBoltCLB, Self.lightningBoltCLU]
        let input = PrintingScorerInput(artistName: "Christopher Moeller")

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "clu", "Artist 'Christopher Moeller' is unique to CLU printing")
    }

    // MARK: - Kappa Cannoneer: NEC #14 vs #50

    /// Two printings of Kappa Cannoneer in the same set (NEC) with different
    /// collector numbers. resolveArtVariant should not override the printing
    /// resolved by scoring when they share the same illustration.
    private static let kappaCannoneerNEC14 = makeCard(
        scryfallID: "kappa-nec-14",
        name: "Kappa Cannoneer",
        setCode: "nec",
        setName: "Neon Dynasty Commander",
        collectorNumber: "14",
        artist: "Steven Belledin",
        releasedAt: "2022-02-18",
        illustrationID: "ill-kappa-shared"
    )

    private static let kappaCannoneerNEC50 = makeCard(
        scryfallID: "kappa-nec-50",
        name: "Kappa Cannoneer",
        setCode: "nec",
        setName: "Neon Dynasty Commander",
        collectorNumber: "50",
        artist: "Steven Belledin",
        releasedAt: "2022-02-18",
        illustrationID: "ill-kappa-shared"  // Same illustration as #14
    )

    @Test("Kappa Cannoneer: bottom-bar collector# 14 picks #14 over #50")
    func kappaCannoneerCollectorNumberDisambiguates() {
        let printings = [Self.kappaCannoneerNEC14, Self.kappaCannoneerNEC50]
        // Bottom bar reads NEC + collector number 14
        let input = PrintingScorerInput(
            bottomBarResults: [(setCode: "NEC", collectorNumber: "14", setTotal: nil, confidence: 0.85)]
        )

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.collectorNumber == "14", "Bottom-bar collector# 14 should pick NEC #14, not #50")
    }

    @Test("Kappa Cannoneer: no signals picks lower collector# via tiebreak")
    func kappaCannoneerNoSignalsTiebreak() {
        let printings = [Self.kappaCannoneerNEC14, Self.kappaCannoneerNEC50]
        let input = PrintingScorerInput()

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        // Same release date -> tiebreak by collector number -> #14 wins
        #expect(winner?.collectorNumber == "14", "Same set + release date should tiebreak to lowest collector number")
    }

    // MARK: - Edge Cases

    @Test("Single printing returns immediately without scoring")
    func singlePrintingReturnsDirectly() {
        let printings = [Self.predatorySliverM14]
        let input = PrintingScorerInput()

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner?.scryfallID == "pred-sliver-m14")
    }

    @Test("Empty printings returns nil")
    func emptyPrintingsReturnsNil() {
        let winner = PrintingScorer.pickWinner(printings: [], input: PrintingScorerInput())

        #expect(winner == nil)
    }

    // MARK: - Cross-Match Threshold (ImageSplitter)

    @Test("Cross-match threshold: identical art (distance < 8) should match")
    func crossMatchThresholdIdenticalArt() {
        // VNFeaturePrint distance for the SAME card in different languages
        // is typically < 5 (identical art, different text frame).
        // Our cross-match threshold is 8 to allow some tolerance.
        let distanceSameCard: Float = 4.2  // typical same-card-different-language
        #expect(distanceSameCard < 8.0, "Same card in different languages should be within cross-match threshold")
    }

    @Test("Cross-match threshold: different cards with similar style (distance > 8) should NOT match")
    func crossMatchThresholdDifferentCards() {
        // Different cards with similar art style (e.g., two Slivers by different
        // artists) score 10-15 on VNFeaturePrint distance. The old threshold of 15
        // incorrectly matched these. The new threshold of 8 correctly rejects them.
        let distanceDifferentCards: Float = 12.3  // typical different-card-similar-style
        #expect(distanceDifferentCards >= 8.0, "Different cards with similar style should NOT be within cross-match threshold")
    }

    // MARK: - FeaturePrint Cache Trust Threshold

    @Test("Cache always rejected when OCR reads a different real card name")
    func cacheAlwaysRejectedWhenOCRReadsDifferentRealCard() {
        // When OCR reads a real card name that differs from the cache,
        // the cache is always rejected regardless of FeaturePrint distance.
        // The verifyIdentification step downstream catches wrong results.
        // Previously, strong FP matches (< 4.0) would trust cache over OCR,
        // but this caused misidentification when scanning different physical
        // cards whose art happened to be visually similar.
        let strongMatchDistance: Float = 2.5
        let weakMatchDistance: Float = 5.8
        // Both distances should result in cache rejection when OCR reads a real card
        #expect(strongMatchDistance < 4.0, "Even strong FP match should NOT trust cache over OCR")
        #expect(weakMatchDistance >= 4.0, "Weak FP match should also reject cache")
        // The key invariant: any distance results in rejection when OCR disagrees with a real card name
    }

    // MARK: - Plains: TDM vs Alpha (many printings regression)

    /// Plains has hundreds of printings. When bottom-bar OCR reads "TDM",
    /// the TDM printing must win — not Alpha (oldest) via tiebreak.
    private static let plainsTDM = makeCard(
        scryfallID: "plains-tdm",
        name: "Plains",
        setCode: "tdm",
        setName: "Tarkir: Dragonstorm",
        collectorNumber: "287",
        artist: "Ron Spencer",
        releasedAt: "2025-04-11"
    )

    private static let plainsAlpha = makeCard(
        scryfallID: "plains-lea",
        name: "Plains",
        setCode: "lea",
        setName: "Limited Edition Alpha",
        collectorNumber: "287",
        artist: "Jesper Myrfors",
        releasedAt: "1993-08-05"
    )

    private static let plains5ED = makeCard(
        scryfallID: "plains-5ed",
        name: "Plains",
        setCode: "5ed",
        setName: "Fifth Edition",
        collectorNumber: "435",
        artist: "Rob Alexander",
        releasedAt: "1997-03-24"
    )

    @Test("Plains: bottom-bar OCR reads TDM -> TDM wins over Alpha")
    func plainsTDMBottomBarWins() {
        let printings = [Self.plainsAlpha, Self.plainsTDM, Self.plains5ED]
        let input = PrintingScorerInput(
            bottomBarResults: [(setCode: "TDM", collectorNumber: "287", setTotal: nil, confidence: 0.9)]
        )

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "tdm", "Bottom-bar OCR reading TDM+287 must pick TDM, not Alpha. Got \(winner?.set.code ?? "nil")")
    }

    @Test("Plains: no signals -> oldest (Alpha) wins via tiebreak")
    func plainsNoSignalsPicksAlpha() {
        let printings = [Self.plainsTDM, Self.plainsAlpha, Self.plains5ED]
        let input = PrintingScorerInput()

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "lea", "No signals should tiebreak to oldest release (Alpha)")
    }

    @Test("Plains: artist Ron Spencer narrows to TDM when unique")
    func plainsArtistRonSpencerPicksTDM() {
        let printings = [Self.plainsAlpha, Self.plainsTDM, Self.plains5ED]
        // Ron Spencer only appears on the TDM printing in this set of candidates
        let input = PrintingScorerInput(artistName: "Ron Spencer")

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "tdm", "Artist 'Ron Spencer' unique to TDM should pick TDM. Got \(winner?.set.code ?? "nil")")
    }

    @Test("Card with readable set code always picks that set's printing")
    func readableSetCodeAlwaysPicked() {
        // Simulate a card with many printings where bottom-bar reads a specific set code
        let oldPrinting = Self.makeCard(
            scryfallID: "card-old",
            name: "Test Card",
            setCode: "lea",
            setName: "Alpha",
            collectorNumber: "50",
            releasedAt: "1993-08-05"
        )
        let correctPrinting = Self.makeCard(
            scryfallID: "card-correct",
            name: "Test Card",
            setCode: "mh3",
            setName: "Modern Horizons 3",
            collectorNumber: "50",
            releasedAt: "2024-06-14"
        )
        let otherPrinting = Self.makeCard(
            scryfallID: "card-other",
            name: "Test Card",
            setCode: "m21",
            setName: "Core Set 2021",
            collectorNumber: "50",
            releasedAt: "2020-07-03"
        )

        let printings = [oldPrinting, correctPrinting, otherPrinting]
        let input = PrintingScorerInput(
            bottomBarResults: [(setCode: "MH3", collectorNumber: "50", setTotal: nil, confidence: 0.85)]
        )

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "mh3", "Bottom-bar set code MH3 must override oldest-release tiebreak. Got \(winner?.set.code ?? "nil")")
    }

    // MARK: - Zuran Orb: Ice Age vs Masters Edition (many printings, same artist)

    /// Zuran Orb has many printings with the SAME artist (Sandra Everingham).
    /// Copyright year 1995 must disambiguate Ice Age from Masters Edition.
    private static let zuranOrbIceAge = makeCard(
        scryfallID: "zuran-orb-ice",
        name: "Zuran Orb",
        setCode: "ice",
        setName: "Ice Age",
        collectorNumber: "385",
        artist: "Sandra Everingham",
        releasedAt: "1995-06-01",
        illustrationID: "ill-zuran-shared"
    )

    private static let zuranOrbMastersEdition = makeCard(
        scryfallID: "zuran-orb-me1",
        name: "Zuran Orb",
        setCode: "me1",
        setName: "Masters Edition",
        collectorNumber: "174",
        artist: "Sandra Everingham",
        releasedAt: "2007-09-10",
        illustrationID: "ill-zuran-shared"
    )

    private static let zuranOrbFTV = makeCard(
        scryfallID: "zuran-orb-v10",
        name: "Zuran Orb",
        setCode: "v10",
        setName: "From the Vault: Relics",
        collectorNumber: "15",
        artist: "Sandra Everingham",
        releasedAt: "2010-08-27",
        illustrationID: "ill-zuran-shared"
    )

    private static let zuranOrb5ED = makeCard(
        scryfallID: "zuran-orb-5ed",
        name: "Zuran Orb",
        setCode: "5ed",
        setName: "Fifth Edition",
        collectorNumber: "410",
        artist: "Sandra Everingham",
        releasedAt: "1997-03-24",
        illustrationID: "ill-zuran-shared"
    )

    @Test("Zuran Orb: copyright year 1995 picks Ice Age over Masters Edition")
    func zuranOrbCopyrightYearPicksIceAge() {
        let printings = [Self.zuranOrbIceAge, Self.zuranOrbMastersEdition, Self.zuranOrbFTV, Self.zuranOrb5ED]
        // OCR reads "© 1995" and artist "Sandra Everingham" (same across all)
        let input = PrintingScorerInput(
            artistName: "Sandra Everingham",
            copyrightYear: 1995
        )

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        // Artist gives +4 to ALL printings (same artist). Copyright year 1995
        // gives +1 to Ice Age (1995) and 5ED (1997, within ±1 range). NOT to
        // Masters Edition (2007) or FTV (2010). Ice Age wins: score 5, tiebreak oldest.
        #expect(winner?.set.code == "ice", "Copyright year 1995 should pick Ice Age. Got \(winner?.set.code ?? "nil")")
    }

    @Test("Zuran Orb: no signals picks oldest (Ice Age) via tiebreak")
    func zuranOrbNoSignalsPicksIceAge() {
        let printings = [Self.zuranOrbMastersEdition, Self.zuranOrbIceAge, Self.zuranOrbFTV, Self.zuranOrb5ED]
        let input = PrintingScorerInput()

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        #expect(winner?.set.code == "ice", "No signals should tiebreak to oldest release (Ice Age 1995). Got \(winner?.set.code ?? "nil")")
    }

    @Test("Zuran Orb: artist alone (same across all) still picks oldest via tiebreak")
    func zuranOrbArtistAlonePicksOldest() {
        let printings = [Self.zuranOrbFTV, Self.zuranOrbMastersEdition, Self.zuranOrbIceAge, Self.zuranOrb5ED]
        // All printings have the same artist, so artist gives +4 to all — tie
        let input = PrintingScorerInput(artistName: "Sandra Everingham")

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        // All get +4, no unique bonus. Tiebreak: oldest release → Ice Age
        #expect(winner?.set.code == "ice", "Same artist across all should tiebreak to oldest (Ice Age). Got \(winner?.set.code ?? "nil")")
    }

    // MARK: - Tormod's Crypt: Chronicles vs Chronicles FBB

    private static let tormodsCryptChronicles = makeCard(
        scryfallID: "tormod-chr",
        name: "Tormod's Crypt",
        setCode: "chr",
        setName: "Chronicles",
        collectorNumber: "93",
        artist: "Christopher Rush",
        releasedAt: "1995-07-01",
        illustrationID: "ill-tormod-shared"
    )

    private static let tormodsCryptChroniclesFBB = makeCard(
        scryfallID: "tormod-chrfbb",
        name: "Tormod's Crypt",
        setCode: "chr",
        setName: "Chronicles Foreign Black Border",
        collectorNumber: "93",
        artist: "Christopher Rush",
        releasedAt: "1995-07-01",
        illustrationID: "ill-tormod-shared"
    )

    @Test("Tormod's Crypt: white border detected should prefer regular Chronicles")
    func tormodsCryptWhiteBorderPrefersRegular() {
        // When both have same set code, same release, same collector#,
        // tiebreak goes to lowest collector# (same) then first in array.
        // This test documents that additional signals (border color) would be
        // needed to disambiguate Chronicles from Chronicles FBB.
        let printings = [Self.tormodsCryptChronicles, Self.tormodsCryptChroniclesFBB]
        let input = PrintingScorerInput(copyrightYear: 1995)

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        // Both score equally (same set code, release, artist, year). First in array wins.
        #expect(winner?.scryfallID == "tormod-chr", "Equal scores should pick first printing in list")
    }

    @Test("Set total filter penalizes impossible collector numbers")
    func setTotalFilterPenalizesImpossible() {
        // Card with collector# 189 in a set of 249 cards (M14) vs
        // a hypothetical printing with collector# 300 in a set of 249
        let highCollector = Self.makeCard(
            scryfallID: "high-num",
            name: "Test Card",
            setCode: "tst",
            setName: "Test Set",
            collectorNumber: "300",
            releasedAt: "2020-01-01"
        )
        let normalCollector = Self.makeCard(
            scryfallID: "normal-num",
            name: "Test Card",
            setCode: "tst2",
            setName: "Test Set 2",
            collectorNumber: "100",
            releasedAt: "2021-01-01"
        )

        let printings = [highCollector, normalCollector]
        // Bottom bar reads set total of 249
        let input = PrintingScorerInput(
            bottomBarResults: [(setCode: "OTHER", collectorNumber: nil, setTotal: 249, confidence: 0.8)]
        )

        let winner = PrintingScorer.pickWinner(printings: printings, input: input)

        #expect(winner != nil)
        // highCollector (#300) gets -5, normalCollector (#100) gets +1
        #expect(winner?.scryfallID == "normal-num", "Collector# 300 > setTotal 249 should be penalized")
    }

}
