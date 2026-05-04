import Foundation

/// Maps Scryfall set identifiers to MTGStocks numeric `set_id`s for promo
/// buckets where MTGStocks lumps every yearly Scryfall set into one
/// catalog entry (FNM, Judge, Prerelease, Buy-A-Box, WPN, etc.).
///
/// Why this exists: MTGStocks reports an empty `""` or `null`
/// `abbreviation` for most promo buckets, so the previous
/// abbreviation/icon_class string match in `lookupID` failed silently and
/// fell through to the card-level default printing — which for an FNM
/// card was usually the original Lorwyn print, not the FNM foil.
///
/// All numeric IDs were verified by scraping `card_set` blocks from
/// MTGStocks print pages on 2026-05-04. Update the table when MTGStocks
/// reorganizes a bucket or when a new promo program needs coverage.
///
/// Known uncovered promo programs (Scryfall audit 2026-05-04). Each
/// would need its MTGStocks `set_id` verified by scraping a print page
/// before being added — never guess a numeric id, that's how we'd
/// reintroduce the wrong-print bug this mapper exists to fix.
///
/// High-volume gaps caught by promo_types:
/// - `playerrewards` (Magic Player Rewards, p03–p11, mpr)
/// - `promopack` (Promo Pack line, ppp1, pmid, pdmu, pone, pdft, …)
/// - `setpromo` (older expansion promos, ugin, p10e, pktk, pori)
/// - `standardshowdown` (pss1–pss5)
/// - `premiereshop` (pmps, pmps06–pmps11)
/// - `tourney` (pcmp, pjas, pjse, psus, pgpx, ppro, p10e)
/// - `convention` (psdc, ps14–ps19)
///
/// Lower priority: `instore`, `gameday`, `storechampionship`,
/// `mediainsert`, `playtest`, `boosterfun`, `playpromo`.
///
/// Sets with no useful promo_types signal (need explicit Scryfall code
/// mapping when prioritized): plg21–plg25 (Love Your LGS), pf19/pf20
/// (older MagicFest), pana (Arena), pl21–pl26/plny (Lunar New Year),
/// pewk (Eternal Weekend), pnat (Nationals), pwcs (Planeswalker
/// Championship), pr23 (RCQ 2023), pjjt, p15a, ptg, slp, pjsc.
enum MTGStocksSetMapper {

    /// Direct Scryfall code → MTGStocks `set_id`. Use for buckets where
    /// the Scryfall code itself is the unique signal (e.g. `plst` is the
    /// only Scryfall code that means "The List").
    private static let setIDByScryfallCode: [String: Int] = [
        "plst": 370,  // The List (PLST)
    ]

    /// Scryfall `promo_types` entry → MTGStocks `set_id`. Use for buckets
    /// that span many yearly Scryfall sets (FNM 2001-2018, Judge Gift
    /// 2000-2025, every prerelease, etc.) — the promo_types tag is the
    /// reliable cross-year signal.
    private static let setIDByPromoType: [String: Int] = [
        "fnm": 113,           // FNM Promos
        "judgegift": 115,     // Judge Promos
        "prerelease": 116,    // Prerelease Cards
        "buyabox": 302,       // Buy-A-Box Promos
        "wpn": 242,           // WPN & Gateway Promos
        "gateway": 242,
        "release": 118,       // Launch Party & Release Event Promos
    ]

    /// Returns the MTGStocks numeric `set_id` for a Scryfall printing,
    /// or `nil` if the printing isn't in a known promo bucket. Callers
    /// should fall through to abbreviation/icon_class matching when
    /// this returns nil — that path covers normal expansions where the
    /// Scryfall code and MTGStocks abbreviation agree (LRW, MMA, etc.).
    static func mtgStocksSetID(scryfallCode: String, promoTypes: [String] = []) -> Int? {
        let lower = scryfallCode.lowercased()
        if let id = setIDByScryfallCode[lower] { return id }
        for pt in promoTypes {
            if let id = setIDByPromoType[pt] { return id }
        }
        return nil
    }

    /// True when the MTGStocks bucket uses an internal sequential
    /// `collector_number` that doesn't map to Scryfall's. Match by
    /// name only inside the bucket — every unique reprint appears once.
    static func usesNameOnlyMatch(scryfallCode: String) -> Bool {
        scryfallCode.lowercased() == "plst"
    }
}
