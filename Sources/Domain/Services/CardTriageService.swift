import Foundation

/// Triage rating for a single Magic card printing.
///
/// Combines five cheap, in-memory signals (format legality, curated
/// staples membership, Reserved List, curated list membership, price
/// floor) into a Tier S/A/B/C verdict. The tier answers "how worth my
/// time is it to pull this from a bulk box?" The signal flags drive
/// per-row badges so the user can see *why* a card was tiered.
struct TriageRating: Equatable, Sendable {

    enum Tier: String, Sendable, CaseIterable {
        /// Sell top dollar — Reserved List, on a curated staples list,
        /// or unit price ≥ $20.
        case s
        /// Worth listing — unit price ≥ $5, or legal in a current
        /// format and ≥ $1.50.
        case a
        /// Low-value singles — ≥ $0.25 and legal somewhere.
        case b
        /// Bulk — leave it in the box.
        case c

        var label: String {
            switch self {
            case .s: return "S"
            case .a: return "A"
            case .b: return "B"
            case .c: return "C"
            }
        }

        /// Sort key — S < A < B < C so `.sorted` puts highest tier first.
        var sortRank: Int {
            switch self {
            case .s: return 0
            case .a: return 1
            case .b: return 2
            case .c: return 3
            }
        }
    }

    let tier: Tier
    let isReservedList: Bool
    /// Format keys this card is a curated staple in (e.g. "modern", "premodern").
    let staplesFormats: [String]
    /// Other curated lists this card hits (e.g. "Classic", "InQuest", "Lands").
    let lists: [String]
    /// Format keys the card is legal-or-restricted in.
    let legalFormats: [String]
    /// USD price used for the tier decision (foil if foil-only, else nonfoil).
    let unitPriceUSD: Double?
}

/// Lazy-built name indexes + tier classifier for the Set Triage feature.
///
/// All data is in-memory; no network or DB calls. Indexes are built once
/// per process via lazy static properties on first `rate(_:)` call.
enum CardTriageService {

    // MARK: - Tunable thresholds

    /// Anything at or above this USD price drops straight into Tier S
    /// regardless of legality or list membership. Tuned from a Tempest
    /// dry-run against ManaBox bulk exports — $20 cleanly separates
    /// "dealer-buylist territory" from "throw on TCGPlayer."
    static let tierSPriceUSD: Double = 20.0

    /// Anything at or above this drops into Tier A unconditionally.
    static let tierAPriceUSD: Double = 5.0

    /// Threshold for the legal-and-cheap branch of Tier A. Raised from
    /// $1 to $1.50 because the $1 floor was sweeping in slow movers
    /// (Shocker, Dauthi Ghoul, Vhati il-Dal) that retail on TCGPlayer
    /// but don't actually move at dealer counters.
    static let tierALegalPriceUSD: Double = 1.50

    /// Tier B floor — below this and the row is bulk regardless.
    static let tierBPriceUSD: Double = 0.25

    /// Format keys evaluated for "legal somewhere." Commander
    /// intentionally omitted per user preference.
    static let consideredFormats: [String] = [
        "modern", "legacy", "pioneer", "standard",
        "pauper", "premodern", "vintage",
    ]

    // MARK: - Indexes

    /// Format key → lowercased name set for staples membership.
    static let staplesByFormat: [String: Set<String>] = [
        "modern": Self.lowerNameSet(ModernStaples.all),
        "legacy": Self.lowerNameSet(LegacyStaples.all),
        "pioneer": Self.lowerNameSet(PioneerStaples.all),
        "standard": Self.lowerNameSet(StandardStaples.all),
        "pauper": Self.lowerNameSet(PauperStaples.all),
        "premodern": Self.lowerNameSet(PremodernStaples.all),
        "vintage": Self.lowerNameSet(VintageStaples.all),
    ]

    /// Reserved List names (lowercased).
    static let reservedListNames: Set<String> = Self.lowerNameSet(ReservedList.all)

    /// Decklist-derived names with basic lands stripped — basics appear
    /// as filler in archetype mainboards but tagging Forest as "in
    /// Classic Decks" is noise.
    static let classicDeckNames: Set<String> = Self.lowerDecklistNames(ClassicArchetypes.all)
    static let inquestDeckNames: Set<String> = Self.lowerDecklistNames(InQuestDecks.all)

    /// Basic land names stripped from decklist-based lists.
    static let basicLandNames: Set<String> = [
        "plains", "island", "swamp", "mountain", "forest", "wastes",
        "snow-covered plains", "snow-covered island", "snow-covered swamp",
        "snow-covered mountain", "snow-covered forest",
    ]

    // MARK: - Classifier

    /// Produces a triage rating for one card printing.
    static func rate(_ card: Card) -> TriageRating {
        let nameKey = card.name.lowercased()

        let isReserved = reservedListNames.contains(nameKey)

        let staplesFormats = consideredFormats.filter { format in
            staplesByFormat[format]?.contains(nameKey) == true
        }

        var lists: [String] = []
        if classicDeckNames.contains(nameKey) { lists.append("Classic") }
        if inquestDeckNames.contains(nameKey) { lists.append("InQuest") }
        if cardMatchesAny(card, in: LandLists.all) { lists.append("Lands") }
        if cardMatchesAny(card, in: CollectibleLands.all) { lists.append("Collectible Lands") }
        if cardMatchesAny(card, in: SecretLairLands.all) { lists.append("Secret Lair") }
        if cardMatchesAny(card, in: JapaneseCollectibles.all) { lists.append("Japanese") }

        let legalFormats = consideredFormats.filter { format in
            switch card.legalities.status(for: format) {
            case .legal, .restricted: return true
            default: return false
            }
        }

        // Foil-only printings (FNM, Secret Lair foil drops, etc.) take
        // their tier from the foil price; everything else uses nonfoil
        // first and falls back to foil if nonfoil is absent.
        let usd = Double(card.prices.usd ?? "")
        let usdFoil = Double(card.prices.usdFoil ?? "")
        let unitPrice: Double? = card.isFoilOnly
            ? (usdFoil ?? usd)
            : (usd ?? usdFoil)

        let tier: TriageRating.Tier = {
            if isReserved { return .s }
            if !staplesFormats.isEmpty { return .s }
            if let p = unitPrice, p >= tierSPriceUSD { return .s }
            if let p = unitPrice {
                if p >= tierAPriceUSD { return .a }
                if !legalFormats.isEmpty && p >= tierALegalPriceUSD { return .a }
                if !legalFormats.isEmpty && p >= tierBPriceUSD { return .b }
            }
            return .c
        }()

        return TriageRating(
            tier: tier,
            isReservedList: isReserved,
            staplesFormats: staplesFormats,
            lists: lists,
            legalFormats: legalFormats,
            unitPriceUSD: unitPrice
        )
    }

    // MARK: - Index builders

    private static func lowerNameSet(_ categories: [LandCategory]) -> Set<String> {
        var out: Set<String> = []
        for cat in categories {
            for name in cat.cardNames {
                out.insert(name.lowercased())
            }
        }
        return out
    }

    private static func lowerDecklistNames(_ archetypes: [ClassicArchetype]) -> Set<String> {
        var out: Set<String> = []
        for arch in archetypes {
            for name in arch.mainboard.keys {
                let lower = name.lowercased()
                if basicLandNames.contains(lower) { continue }
                out.insert(lower)
            }
            if let sb = arch.sideboard {
                for name in sb.keys {
                    let lower = name.lowercased()
                    if basicLandNames.contains(lower) { continue }
                    out.insert(lower)
                }
            }
        }
        return out
    }

    /// Card-against-LandCategory matcher that respects setCodes.
    /// Empty `setCodes` = name-only match (LandLists). Non-empty =
    /// must match the printing's set code (CollectibleLands, Secret
    /// Lair, Japanese).
    private static func cardMatchesAny(_ card: Card, in categories: [LandCategory]) -> Bool {
        let nameKey = card.name.lowercased()
        let setKey = card.set.code.lowercased()
        for cat in categories {
            let nameMatch = cat.cardNames.contains { $0.lowercased() == nameKey }
            if !nameMatch { continue }
            if cat.setCodes.isEmpty { return true }
            if cat.setCodes.contains(where: { $0.lowercased() == setKey }) {
                return true
            }
        }
        return false
    }
}
