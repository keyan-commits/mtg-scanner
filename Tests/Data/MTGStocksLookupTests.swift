import Testing
import Foundation
@testable import MTGCardScanner

/// Unit tests for `MTGStocksService.selectPrintID` — the pure printing-
/// resolution logic. Payloads are abridged but field-accurate copies of
/// real MTGStocks `/prints/<id>` `sets[]` entries scraped on 2026-05-04
/// (Spellstutter Sprite, Vampiric Tutor, Brainstorm). Add a fixture
/// here when you discover a new bucket to cover.
@Suite("MTGStocks selectPrintID")
struct MTGStocksLookupTests {

    // MARK: - Spellstutter Sprite fixtures (FNM, LRW, MMA, PLST)

    /// Verbatim from `mtgstocks.com/prints/20609-spellstutter-sprite`
    /// `sets[]` (only the keys `selectPrintID` reads).
    static let spellstutterSpriteSets: [[String: Any]] = [
        [   // Lorwyn — normal expansion, abbreviation matches
            "id": 3274,
            "name": "Spellstutter Sprite",
            "abbreviation": "LRW",
            "icon_class": "lrw",
            "collector_number": 89,
            "set_id": 17,
            "set_name": "Lorwyn",
        ],
        [   // Modern Masters — normal expansion
            "id": 21005,
            "name": "Spellstutter Sprite",
            "abbreviation": "MMA",
            "icon_class": "mma",
            "collector_number": 65,
            "set_id": 220,
            "set_name": "Modern Masters",
        ],
        [   // FNM Promos — bucket with abbreviation "FNM" that doesn't
            // match Scryfall code "f11"
            "id": 20609,
            "name": "Spellstutter Sprite",
            "abbreviation": "FNM",
            "icon_class": "star",
            "collector_number": 2,
            "set_id": 113,
            "set_name": "FNM Promos",
        ],
        [   // The List — abbreviation "PLST" but MTGStocks uses an
            // internal sequential CN (1252) that doesn't map to
            // Scryfall's "LRW-89"
            "id": 97785,
            "name": "Spellstutter Sprite",
            "abbreviation": "PLST",
            "icon_class": "planeswalker",
            "collector_number": 1252,
            "set_id": 370,
            "set_name": "The List",
        ],
    ]

    @Test("FNM print resolves by promo_types + collector number")
    func fnmPrintResolves() {
        // Scryfall code `f11`, promo_types ["tourney", "fnm"], CN "2"
        // → MTGStocks set_id 113 + CN 2 → print 20609.
        let id = MTGStocksService.selectPrintID(
            from: Self.spellstutterSpriteSets,
            cardName: "Spellstutter Sprite",
            scryfallSetCode: "f11",
            collectorNumber: "2",
            promoTypes: ["tourney", "fnm"]
        )
        #expect(id == 20609)
    }

    @Test("Lorwyn print resolves by abbreviation match")
    func lorwynPrintResolves() {
        // Normal expansion: Scryfall `lrw` matches MTGStocks `LRW`.
        let id = MTGStocksService.selectPrintID(
            from: Self.spellstutterSpriteSets,
            cardName: "Spellstutter Sprite",
            scryfallSetCode: "lrw",
            collectorNumber: "89",
            promoTypes: []
        )
        #expect(id == 3274)
    }

    @Test("Modern Masters print resolves by abbreviation match")
    func modernMastersPrintResolves() {
        let id = MTGStocksService.selectPrintID(
            from: Self.spellstutterSpriteSets,
            cardName: "Spellstutter Sprite",
            scryfallSetCode: "mma",
            collectorNumber: "65",
            promoTypes: []
        )
        #expect(id == 21005)
    }

    @Test("The List print resolves by name only (CN ignored)")
    func theListPrintResolves() {
        // Scryfall encodes plst CN as "LRW-89"; MTGStocks uses 1252.
        // The name-only branch picks the right print regardless.
        let id = MTGStocksService.selectPrintID(
            from: Self.spellstutterSpriteSets,
            cardName: "Spellstutter Sprite",
            scryfallSetCode: "plst",
            collectorNumber: "LRW-89",
            promoTypes: []
        )
        #expect(id == 97785)
    }

    // MARK: - Empty-abbreviation buckets (Judge, Prerelease, Buy-A-Box)

    /// Abridged Vampiric Tutor `sets[]` — Judge bucket has empty
    /// abbreviation. Verified 2026-05-04.
    static let vampiricTutorSets: [[String: Any]] = [
        [   // Original Visions print
            "id": 1234,
            "name": "Vampiric Tutor",
            "abbreviation": "VIS",
            "icon_class": "vis",
            "collector_number": 71,
            "set_id": 50,
            "set_name": "Visions",
        ],
        [   // Judge promo — empty abbreviation, set_id 115
            "id": 20713,
            "name": "Vampiric Tutor",
            "abbreviation": "",
            "icon_class": "default",
            "collector_number": 2,
            "set_id": 115,
            "set_name": "Judge Promos",
        ],
    ]

    @Test("Judge promo resolves via promo_types despite empty abbreviation")
    func judgePromoResolves() {
        // Abbreviation match cannot work — MTGStocks reports "" for the
        // judge bucket. The promo_types signal "judgegift" is the bridge.
        let id = MTGStocksService.selectPrintID(
            from: Self.vampiricTutorSets,
            cardName: "Vampiric Tutor",
            scryfallSetCode: "j15",
            collectorNumber: "2",
            promoTypes: ["judgegift"]
        )
        #expect(id == 20713)
    }

    @Test("Prerelease bucket resolves via promo_types")
    func prereleaseResolves() {
        let sets: [[String: Any]] = [
            [
                "id": 121510,
                "name": "Progenitus",
                "abbreviation": "",
                "icon_class": "default",
                "collector_number": 244,
                "set_id": 116,
                "set_name": "Prerelease Cards",
            ],
        ]
        let id = MTGStocksService.selectPrintID(
            from: sets,
            cardName: "Progenitus",
            scryfallSetCode: "pmps11",  // example Scryfall prerelease code
            collectorNumber: "244",
            promoTypes: ["prerelease", "datestamped"]
        )
        #expect(id == 121510)
    }

    @Test("Buy-A-Box resolves via promo_types despite null abbreviation")
    func buyABoxResolves() {
        let sets: [[String: Any]] = [
            [
                "id": 40477,
                "name": "Impervious Greatwurm",
                // abbreviation is JSON null in the real payload — modeled
                // here as missing key, which behaves identically through
                // the optional cast.
                "icon_class": "default",
                "collector_number": 273,
                "set_id": 302,
                "set_name": "Buy-A-Box Promos",
            ],
        ]
        let id = MTGStocksService.selectPrintID(
            from: sets,
            cardName: "Impervious Greatwurm",
            scryfallSetCode: "pgrn",
            collectorNumber: "273",
            promoTypes: ["buyabox"]
        )
        #expect(id == 40477)
    }

    // MARK: - Negative cases

    @Test("Returns nil when no match found and no fallback applies")
    func returnsNilForUnknownPrint() {
        // Scryfall code with no bucket mapping, no abbreviation match —
        // selectPrintID returns nil so the caller can fall back to the
        // card-level default rather than confidently picking a wrong
        // print (which is what the old code did).
        let id = MTGStocksService.selectPrintID(
            from: Self.spellstutterSpriteSets,
            cardName: "Spellstutter Sprite",
            scryfallSetCode: "doesnotexist",
            collectorNumber: "999",
            promoTypes: []
        )
        #expect(id == nil)
    }

    @Test("FNM lookup with wrong CN returns nil, not the first FNM print")
    func fnmWrongCNDoesNotFallThrough() {
        // Old "first printing in set" fallback would have returned 20609
        // regardless of CN. The new logic returns nil so the caller
        // falls back to the card-level default — better than confidently
        // returning the wrong print.
        let id = MTGStocksService.selectPrintID(
            from: Self.spellstutterSpriteSets,
            cardName: "Spellstutter Sprite",
            scryfallSetCode: "f11",
            collectorNumber: "999",
            promoTypes: ["fnm"]
        )
        #expect(id == nil)
    }

    @Test("Empty sets array returns nil")
    func emptySetsReturnsNil() {
        let id = MTGStocksService.selectPrintID(
            from: [],
            cardName: "Spellstutter Sprite",
            scryfallSetCode: "f11",
            collectorNumber: "2",
            promoTypes: ["fnm"]
        )
        #expect(id == nil)
    }

    // MARK: - Setmapper unit checks

    @Test("Mapper returns set_id 113 for FNM promo_types")
    func mapperFnm() {
        #expect(MTGStocksSetMapper.mtgStocksSetID(scryfallCode: "f11", promoTypes: ["fnm"]) == 113)
    }

    @Test("Mapper returns set_id 370 for plst Scryfall code")
    func mapperPlst() {
        #expect(MTGStocksSetMapper.mtgStocksSetID(scryfallCode: "plst") == 370)
    }

    @Test("Mapper returns nil for normal expansion")
    func mapperNormalExpansion() {
        // LRW is a regular expansion — no bucket override needed,
        // falls through to abbreviation match.
        #expect(MTGStocksSetMapper.mtgStocksSetID(scryfallCode: "lrw") == nil)
    }

    @Test("Mapper flags plst as name-only matching")
    func mapperPlstIsNameOnly() {
        #expect(MTGStocksSetMapper.usesNameOnlyMatch(scryfallCode: "plst") == true)
        #expect(MTGStocksSetMapper.usesNameOnlyMatch(scryfallCode: "lrw") == false)
        #expect(MTGStocksSetMapper.usesNameOnlyMatch(scryfallCode: "f11") == false)
    }

    // MARK: - Foil-aware vendor selection

    /// Vendor JSON shape mirrors a real /prints/{id} response — TCGPlayer
    /// exposes `avg` (non-foil aggregate) AND `foil` (foil aggregate).
    /// For a print that only exists in foil, `avg` is misleading because
    /// it can be populated by sales of similarly-named non-foil reprints
    /// MTGStocks groups together. Foil-only callers must prefer `foil`.
    static let dualFinishVendorJSON: [String: Any] = [
        "id": 20609,
        "name": "Spellstutter Sprite",
        "tcgplayer": [
            "url": "https://tcgplayer.example",
            "latestPrice": [
                "avg": 6.0,
                "foil": 30.45,
                "low": 4.0,
                "market": 5.95,
                "high": 17.85,
            ],
        ],
    ]

    @Test("Foil-only card prefers foil aggregate over avg in vendor prices")
    func foilOnlyPrefersFoilVendorPrice() {
        guard let card = MTGStocksCard.from(json: Self.dualFinishVendorJSON, isFoilOnly: true),
              let tcg = card.vendorPrices.first(where: { $0.vendor == "TCGPlayer" }) else {
            Issue.record("Card or TCGPlayer vendor missing")
            return
        }
        #expect(tcg.price == 30.45)
        #expect(tcg.isFoil == true)
    }

    @Test("Non-foil TCGPlayer uses market field (not avg)")
    func nonFoilUsesMarket() {
        // TCGPlayer specifically prefers `latestPrice.market` so the
        // Compare Prices vendor row matches the dedicated MARKET tier
        // shown in the TCGPlayer (NM) section above.
        guard let card = MTGStocksCard.from(json: Self.dualFinishVendorJSON, isFoilOnly: false),
              let tcg = card.vendorPrices.first(where: { $0.vendor == "TCGPlayer" }) else {
            Issue.record("Card or TCGPlayer vendor missing")
            return
        }
        #expect(tcg.price == 5.95)
        #expect(tcg.isFoil == false)
    }

    @Test("Foil-only history prefers foil series over avg")
    func foilOnlyHistoryPrefersFoil() throws {
        let json = """
        {
          "avg": [[1700000000000, 6.0]],
          "foil": [[1700000000000, 30.45]],
          "market": null,
          "market_foil": null,
          "low": null,
          "high": null
        }
        """.data(using: .utf8)!
        let history = try JSONDecoder().decode(MTGStocksPriceHistory.self, from: json)
        let foilPrices = history.averagePrices(preferFoil: true)
        let nonFoilPrices = history.averagePrices(preferFoil: false)
        #expect(foilPrices.first?.price == 30.45)
        #expect(nonFoilPrices.first?.price == 6.0)
    }

    @Test("tcgMid uses latestPrice.avg, tcgMarket uses latestPrice.market")
    func tcgMidAndMarketUseDistinctFields() {
        // ManaBox / TCGPlayer's product page show LOW / MID / MARKET as
        // three separate values. MID is the median of listings (`avg`)
        // and MARKET is TCGPlayer's algorithmic reference (`market`) —
        // they're often different and we must surface both, not collapse.
        guard let card = MTGStocksCard.from(json: Self.dualFinishVendorJSON) else {
            Issue.record("Card parse failed")
            return
        }
        #expect(card.tcgLow == 4.0)
        #expect(card.tcgMid == 6.0)         // from latestPrice.avg
        #expect(card.tcgMarket == 5.95)     // from latestPrice.market
    }

    @Test("Compare Prices TCGPlayer row uses market, not avg")
    func compareTCGPlayerUsesMarket() {
        // For Necropotence-style mid-rally cards, MID ($63) and MARKET
        // ($49) diverge significantly. The Compare Prices vendor list
        // is meant to mirror the canonical TCGPlayer reference, so the
        // TCGPlayer row uses `market` (matching the dedicated TCGPlayer
        // tier section). Other vendors don't have a `market` field and
        // continue to use `avg`.
        guard let card = MTGStocksCard.from(json: Self.dualFinishVendorJSON),
              let tcg = card.vendorPrices.first(where: { $0.vendor == "TCGPlayer" }) else {
            Issue.record("TCGPlayer vendor missing")
            return
        }
        #expect(tcg.price == 5.95)   // market, not avg (6.0)
    }

    @Test("tcgMarket falls through to market_foil then foil when market missing")
    func tcgMarketFallsThrough() {
        let json: [String: Any] = [
            "id": 1,
            "name": "Foil Only",
            "tcgplayer": [
                "latestPrice": [
                    "low": 4.0,
                    "foil": 28.50,
                    "market_foil": 28.0,
                ],
            ],
        ]
        guard let card = MTGStocksCard.from(json: json) else {
            Issue.record("Card parse failed")
            return
        }
        // market null, market_foil 28.0 wins
        #expect(card.tcgMarket == 28.0)
        // tcgMid null → falls through to foil
        #expect(card.tcgMid == 28.50)
    }

    @Test("Foil-only history falls back through foil ladder when avg missing")
    func foilOnlyHistoryFallsThroughLadder() throws {
        // foil missing → marketFoil → avg → market.
        let json = """
        {
          "avg": null,
          "foil": null,
          "market": null,
          "market_foil": [[1700000000000, 28.5]],
          "low": null,
          "high": null
        }
        """.data(using: .utf8)!
        let history = try JSONDecoder().decode(MTGStocksPriceHistory.self, from: json)
        #expect(history.averagePrices(preferFoil: true).first?.price == 28.5)
    }
}
