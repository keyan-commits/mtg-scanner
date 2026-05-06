import Testing
import Foundation
@testable import MTGCardScanner

@Suite("FBListingFormatter — sale post text builder")
struct FBListingFormatterTests {

    private static let usdToPHP: Double = 65.0

    private static func makePrinting(set: String, releasedAt: String?) -> Card {
        Card(
            scryfallID: "\(set)-x",
            name: "Watery Grave",
            manaCost: nil,
            typeLine: "Land",
            oracleText: nil,
            set: SetInfo(code: set, name: set.uppercased(), setType: "expansion", iconSVGURI: nil, releasedAt: releasedAt),
            collectorNumber: "286",
            rarity: .rare,
            artist: nil,
            releasedAt: releasedAt,
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
            finishes: ["nonfoil", "foil"]
        )
    }

    // MARK: - formatPricePHK

    @Test("Whole-thousand prices format without decimals")
    func wholeThousand() {
        // $148.69 × 65 = ₱9,664.85 → 9.5k... actually 9664/1000=9.66, half-step round = 9.5k
        // Use $138 × 65 = ₱8,970 → 9.0k → "9k"
        let s = FBListingFormatter.formatPricePHK(usd: 138.0, usdToPHP: Self.usdToPHP)
        #expect(s == "9k")
    }

    @Test("Half-thousand prices keep the .5 suffix")
    func halfThousand() {
        // $40 × 65 = ₱2,600 → 2.6k → half-step round = 2.5k
        let s = FBListingFormatter.formatPricePHK(usd: 40.0, usdToPHP: Self.usdToPHP)
        #expect(s == "2.5k")
    }

    @Test("Round to nearest 0.5k matches user's hand-typed posts")
    func roundsToHalf() {
        // ₱2,000 → 2k
        #expect(FBListingFormatter.formatPricePHK(usd: 2000.0 / 65.0, usdToPHP: Self.usdToPHP) == "2k")
        // ₱2,499 → 2.5k (rounds up)
        #expect(FBListingFormatter.formatPricePHK(usd: 2499.0 / 65.0, usdToPHP: Self.usdToPHP) == "2.5k")
        // ₱2,250 → 2.5k (rounds up — exactly halfway between 2k and 2.5k)
        #expect(FBListingFormatter.formatPricePHK(usd: 2250.0 / 65.0, usdToPHP: Self.usdToPHP) == "2.5k")
    }

    @Test("Missing or zero price renders as ?")
    func missingPriceFallback() {
        #expect(FBListingFormatter.formatPricePHK(usd: nil, usdToPHP: Self.usdToPHP) == "?")
        #expect(FBListingFormatter.formatPricePHK(usd: 0, usdToPHP: Self.usdToPHP) == "?")
        #expect(FBListingFormatter.formatPricePHK(usd: 10, usdToPHP: 0) == "?")
    }

    // MARK: - formatLine

    @Test("Watery Grave RAV foil OG matches the user's hand-typed format")
    func wateryGraveExample() {
        // Real numbers from the user's screenshot: foil USD $148.69 → ₱9,664 → 9.5k
        let line = FBListingFormatter.formatLine(
            FBListingFormatter.LineSpec(
                quantity: 1,
                cardName: "Watery Grave",
                setCode: "rav",
                isFoil: true,
                isOriginalPrinting: true,
                priceUSD: 148.69
            ),
            usdToPHP: Self.usdToPHP
        )
        #expect(line == "✅1x Watery Grave [RAV] [FOIL] [OG] = 9.5k")
    }

    @Test("Underground River 10E foil non-OG omits the [OG] tag")
    func undergroundRiver10E() {
        let line = FBListingFormatter.formatLine(
            FBListingFormatter.LineSpec(
                quantity: 1,
                cardName: "Underground River",
                setCode: "10E",
                isFoil: true,
                isOriginalPrinting: false,
                priceUSD: 30.0    // ₱1,950 → 2k
            ),
            usdToPHP: Self.usdToPHP
        )
        #expect(line == "✅1x Underground River [10E] [FOIL] = 2k")
    }

    @Test("Nonfoil OG line drops [FOIL] but keeps [OG]")
    func nonfoilOG() {
        let line = FBListingFormatter.formatLine(
            FBListingFormatter.LineSpec(
                quantity: 2,
                cardName: "Watery Grave",
                setCode: "rav",
                isFoil: false,
                isOriginalPrinting: true,
                priceUSD: 18.0
            ),
            usdToPHP: Self.usdToPHP
        )
        #expect(line == "✅2x Watery Grave [RAV] [OG] = 1k")
    }

    @Test("Plain reprint (nonfoil, not OG) gets only [SET]")
    func plainReprint() {
        let line = FBListingFormatter.formatLine(
            FBListingFormatter.LineSpec(
                quantity: 4,
                cardName: "Counterspell",
                setCode: "mh2",
                isFoil: false,
                isOriginalPrinting: false,
                priceUSD: 1.0    // ₱65 → 0k... edge case
            ),
            usdToPHP: Self.usdToPHP
        )
        #expect(line == "✅4x Counterspell [MH2] = 0k")
    }

    // MARK: - formatPost

    @Test("formatPost concatenates header + lines + footer")
    func fullPostShape() {
        let lines: [FBListingFormatter.LineSpec] = [
            .init(quantity: 1, cardName: "Watery Grave", setCode: "rav",
                  isFoil: true, isOriginalPrinting: true, priceUSD: 148.69),
            .init(quantity: 1, cardName: "Underground River", setCode: "10e",
                  isFoil: true, isOriginalPrinting: false, priceUSD: 30.0),
        ]
        let post = FBListingFormatter.formatPost(lines: lines, usdToPHP: Self.usdToPHP)
        #expect(post.contains(FBListingFormatter.header))
        #expect(post.contains("✅1x Watery Grave [RAV] [FOIL] [OG] = 9.5k"))
        #expect(post.contains("✅1x Underground River [10E] [FOIL] = 2k"))
        #expect(post.contains("Location: Ortigas / Pasig"))
        #expect(post.contains("Mode of Payment: GCash"))
    }

    @Test("formatPost respects a custom footer override")
    func customFooter() {
        let post = FBListingFormatter.formatPost(
            lines: [
                .init(quantity: 1, cardName: "X", setCode: "abc",
                      isFoil: false, isOriginalPrinting: false, priceUSD: 10)
            ],
            usdToPHP: Self.usdToPHP,
            footer: "Custom footer text"
        )
        #expect(post.hasSuffix("Custom footer text"))
        #expect(!post.contains("Ortigas"))
    }

    // MARK: - isOriginalPrinting

    @Test("Earliest-released printing is OG (Watery Grave RAV vs reprints)")
    func ogEarliestRelease() {
        let printings = [
            Self.makePrinting(set: "rav", releasedAt: "2005-10-07"),
            Self.makePrinting(set: "gtc", releasedAt: "2013-02-01"),
            Self.makePrinting(set: "rna", releasedAt: "2019-01-25"),
        ]
        #expect(FBListingFormatter.isOriginalPrinting(setCode: "rav", printings: printings))
        #expect(!FBListingFormatter.isOriginalPrinting(setCode: "gtc", printings: printings))
        #expect(!FBListingFormatter.isOriginalPrinting(setCode: "rna", printings: printings))
    }

    @Test("Set code comparison is case-insensitive (Scryfall codes are lowercase)")
    func ogCaseInsensitive() {
        let printings = [Self.makePrinting(set: "lea", releasedAt: "1993-08-05")]
        #expect(FBListingFormatter.isOriginalPrinting(setCode: "LEA", printings: printings))
        #expect(FBListingFormatter.isOriginalPrinting(setCode: "lea", printings: printings))
    }

    @Test("Empty printings list returns false (no signal)")
    func ogEmptyList() {
        #expect(!FBListingFormatter.isOriginalPrinting(setCode: "rav", printings: []))
    }

    @Test("Printing with nil releasedAt sorts last (won't accidentally win the OG check)")
    func ogNilDateSortsLast() {
        let printings = [
            Self.makePrinting(set: "ghost", releasedAt: nil),
            Self.makePrinting(set: "rav", releasedAt: "2005-10-07"),
        ]
        #expect(FBListingFormatter.isOriginalPrinting(setCode: "rav", printings: printings))
        #expect(!FBListingFormatter.isOriginalPrinting(setCode: "ghost", printings: printings))
    }
}
