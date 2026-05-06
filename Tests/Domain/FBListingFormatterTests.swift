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

    @Test("Price renders as precise PHP integer with thousand separators")
    func precisePHPFormatting() {
        // $148.69 × 65 = ₱9,664.85 → rounded to integer = 9,665
        #expect(FBListingFormatter.formatPricePHK(usd: 148.69, usdToPHP: Self.usdToPHP) == "9,665")
        // $30 × 65 = ₱1,950
        #expect(FBListingFormatter.formatPricePHK(usd: 30.0, usdToPHP: Self.usdToPHP) == "1,950")
        // $1 × 65 = ₱65 (no separator at this magnitude)
        #expect(FBListingFormatter.formatPricePHK(usd: 1.0, usdToPHP: Self.usdToPHP) == "65")
    }

    @Test("Sub-hundred prices format without separators")
    func subHundredPrice() {
        // $0.50 × 65 = ₱32.50 → 33
        #expect(FBListingFormatter.formatPricePHK(usd: 0.50, usdToPHP: Self.usdToPHP) == "33")
    }

    @Test("Missing or zero price renders as ?")
    func missingPriceFallback() {
        #expect(FBListingFormatter.formatPricePHK(usd: nil, usdToPHP: Self.usdToPHP) == "?")
        #expect(FBListingFormatter.formatPricePHK(usd: 0, usdToPHP: Self.usdToPHP) == "?")
        #expect(FBListingFormatter.formatPricePHK(usd: 10, usdToPHP: 0) == "?")
    }

    // MARK: - formatLine

    @Test("Watery Grave RAV foil OG renders with the precise PHP price")
    func wateryGraveExample() {
        // Real numbers from the user's screenshot: foil USD $148.69 → ₱9,665
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
        #expect(line == "✅1x Watery Grave [RAV] [FOIL] [OG] = 9,665")
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
                priceUSD: 30.0    // ₱1,950
            ),
            usdToPHP: Self.usdToPHP
        )
        #expect(line == "✅1x Underground River [10E] [FOIL] = 1,950")
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
        #expect(line == "✅2x Watery Grave [RAV] [OG] = 1,170")
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
                priceUSD: 1.0    // ₱65
            ),
            usdToPHP: Self.usdToPHP
        )
        #expect(line == "✅4x Counterspell [MH2] = 65")
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
        #expect(post.contains("✅1x Watery Grave [RAV] [FOIL] [OG] = 9,665"))
        #expect(post.contains("✅1x Underground River [10E] [FOIL] = 1,950"))
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
