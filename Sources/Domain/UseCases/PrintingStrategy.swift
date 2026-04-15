import Foundation

/// How a card name should be resolved into a concrete printing when
/// the source data only carries the name (e.g., MTGTop8 deck rows).
///
/// All variants operate over the full list of printings returned by
/// `CardRepositoryProtocol.findAllPrintings(name:)` and pick exactly
/// one printing per card. If a strategy's filter matches no printings
/// (e.g. "First Print Borderless" for a card that never had a
/// borderless printing), the strategy falls back to the unfiltered
/// version of itself so the user always sees *some* card rather than
/// an empty row.
enum PrintingStrategy: String, CaseIterable, Identifiable, Sendable {
    /// Oldest printing regardless of border style. Always returns the
    /// historical original — the iconic version of the card.
    case firstPrint = "first-print"
    /// Oldest printing with a standard black/white/silver/gold border.
    /// Excludes borderless variants. Useful when you want the iconic
    /// art *with* the traditional card frame.
    case firstPrintNormal = "first-print-normal"
    /// Oldest printing with a borderless treatment. For users who
    /// prefer the modern premium look.
    case firstPrintBorderless = "first-print-borderless"
    /// Lowest USD price (falls back to EUR), any border.
    case cheapest = "cheapest"
    /// Lowest USD price, restricted to standard-bordered printings.
    case cheapestNormal = "cheapest-normal"
    /// Highest USD price (falls back to EUR), any border. Surfaces
    /// the premium showcase / borderless / serialized variants users
    /// might want to chase.
    case mostExpensive = "most-expensive"

    var id: String { rawValue }

    /// Human label shown in pickers.
    var displayName: String {
        switch self {
        case .firstPrint: return "First Print"
        case .firstPrintNormal: return "First Print (Normal Border)"
        case .firstPrintBorderless: return "First Print (Borderless)"
        case .cheapest: return "Cheapest"
        case .cheapestNormal: return "Cheapest (Normal Border)"
        case .mostExpensive: return "Most Expensive"
        }
    }

    /// SF Symbol used in toolbars and settings.
    var iconName: String {
        switch self {
        case .firstPrint, .firstPrintNormal, .firstPrintBorderless:
            return "clock.arrow.circlepath"
        case .cheapest, .cheapestNormal:
            return "tag.fill"
        case .mostExpensive:
            return "dollarsign.circle.fill"
        }
    }

    /// True if this strategy excludes borderless printings.
    var requiresNormalBorder: Bool {
        switch self {
        case .firstPrintNormal, .cheapestNormal: return true
        default: return false
        }
    }

    /// True if this strategy *only* picks borderless printings.
    var requiresBorderless: Bool {
        self == .firstPrintBorderless
    }
}

// MARK: - Selection logic

extension PrintingStrategy {

    /// Standard MTG borders that count as "normal". Borderless and
    /// promo borders are excluded.
    private static let normalBorders: Set<String> = [
        "black", "white", "silver", "gold",
    ]

    /// Scryfall `frame_effects` values that disqualify a printing
    /// from "normal border", regardless of `borderColor`. Borderless
    /// variants in NEC and similar sets are tagged with `borderColor:
    /// "black"` but `frame_effects: ["borderless"]` — without checking
    /// frame effects, the filter would let them through.
    private static let specialTreatments: Set<String> = [
        "borderless", "showcase", "extendedart", "etched",
    ]

    /// Picks the printing that best matches this strategy from the
    /// given candidate list. Never returns nil as long as `printings`
    /// is non-empty.
    ///
    /// Semantics:
    /// - **First Print** — oldest printing by `releasedAt`, any border.
    /// - **First Print (Normal Border)** — the card *from the original
    ///   set*, preferring a normal-bordered variant within that set.
    ///   If the original set only has special treatments (e.g. all
    ///   borderless), returns whatever the original set offers — never
    ///   skips to a later set just to find a normal border.
    /// - **First Print (Borderless)** — the card *from the original
    ///   set*, preferring a borderless variant within that set. If the
    ///   original set has no borderless variant, falls back to a
    ///   normal-bordered variant from that same set — never skips to a
    ///   later set's borderless reprint.
    /// - **Cheapest** — lowest USD price across all printings, any
    ///   border.
    /// - **Cheapest (Normal Border)** — lowest USD price restricted to
    ///   normal-bordered printings (any set).
    func pick(from printings: [Card]) -> Card? {
        guard !printings.isEmpty else { return nil }

        switch self {
        case .firstPrint:
            return Self.oldest(in: printings)

        case .firstPrintNormal:
            let firstSetPrintings = Self.printingsInFirstPrintSet(printings)
            if let normal = firstSetPrintings.first(where: Self.isNormalBorder) {
                return normal
            }
            // Original set has nothing normal-bordered; use whatever
            // it has rather than reaching for a later set.
            return firstSetPrintings.first ?? printings.first

        case .firstPrintBorderless:
            let firstSetPrintings = Self.printingsInFirstPrintSet(printings)
            if let borderless = firstSetPrintings.first(where: Self.isBorderless) {
                return borderless
            }
            // Original set has no borderless variant — fall back to a
            // normal-bordered one from the same set, then to anything
            // from that set. Never escapes to a later set.
            if let normal = firstSetPrintings.first(where: Self.isNormalBorder) {
                return normal
            }
            return firstSetPrintings.first ?? printings.first

        case .cheapest:
            return Self.cheapest(in: printings)

        case .cheapestNormal:
            let filtered = printings.filter(Self.isNormalBorder)
            if let chosen = Self.cheapest(in: filtered) { return chosen }
            return Self.cheapest(in: printings)

        case .mostExpensive:
            return Self.mostExpensive(in: printings)
        }
    }

    /// Set types that should NOT be considered "the first print set".
    /// Judge promos, prerelease promos, and similar special products
    /// often have release dates BEFORE the main expansion, but the
    /// user expects "First Print" to mean the expansion, not a promo.
    private static let promoSetTypes: Set<String> = [
        "promo", "memorabilia", "token", "vanguard", "funny",
        "treasure_chest", "box",
    ]

    /// All printings that belong to the same set as the oldest
    /// NON-PROMO printing. Skips promo/special sets so "First Print"
    /// returns the main expansion (e.g., Urza's Saga for Gaea's
    /// Cradle, not the Judge Gift Cards that released earlier).
    /// Falls back to ANY oldest printing if every printing is a promo.
    private static func printingsInFirstPrintSet(_ printings: [Card]) -> [Card] {
        // Try non-promo printings first
        let mainPrintings = printings.filter { !promoSetTypes.contains($0.set.setType) }
        let source = mainPrintings.isEmpty ? printings : mainPrintings
        guard let oldest = Self.oldest(in: source) else { return printings }
        let setCode = oldest.set.code
        return printings.filter { $0.set.code == setCode }
    }

    // MARK: - Filters

    private static func isNormalBorder(_ card: Card) -> Bool {
        // Exclude special frame treatments first — borderless/showcase/
        // extendedart variants in modern sets are tagged with
        // borderColor "black" but frame_effects ["borderless"], so
        // checking borderColor alone is not enough.
        for effect in card.frameEffects {
            if specialTreatments.contains(effect.lowercased()) {
                return false
            }
        }
        guard let border = card.borderColor?.lowercased() else {
            // Missing border data → assume normal (most cards lack
            // borderColor metadata in older Scryfall imports).
            return true
        }
        return normalBorders.contains(border)
    }

    private static func isBorderless(_ card: Card) -> Bool {
        // Borderless either via borderColor field or via frame_effects
        // (modern sets tag the borderless variant with both, but
        // showcase/extendedart variants only show up in frame_effects).
        if card.borderColor?.lowercased() == "borderless" {
            return true
        }
        return card.frameEffects.contains { $0.lowercased() == "borderless" }
    }

    // MARK: - Selectors

    /// Oldest printing by `releasedAt`. Strings sort lexicographically
    /// and ISO-8601 dates (yyyy-MM-dd) sort identically to chronological.
    private static func oldest(in printings: [Card]) -> Card? {
        guard !printings.isEmpty else { return nil }
        return printings.min { lhs, rhs in
            (lhs.releasedAt ?? "9999") < (rhs.releasedAt ?? "9999")
        }
    }

    /// Lowest non-nil USD price; falls back to EUR; falls back to the
    /// first printing if no prices are listed.
    private static func cheapest(in printings: [Card]) -> Card? {
        guard !printings.isEmpty else { return nil }
        let priced = pricedPrintings(printings)
        return priced.min { $0.1 < $1.1 }?.0 ?? printings.first
    }

    /// Highest non-nil USD price; falls back to EUR; falls back to the
    /// first printing if no prices are listed.
    private static func mostExpensive(in printings: [Card]) -> Card? {
        guard !printings.isEmpty else { return nil }
        let priced = pricedPrintings(printings)
        return priced.max { $0.1 < $1.1 }?.0 ?? printings.first
    }

    /// Pairs each card with its best-available price (USD, then EUR).
    /// Cards with no listed price in either currency are dropped.
    private static func pricedPrintings(_ printings: [Card]) -> [(Card, Double)] {
        printings.compactMap { card in
            if let usd = card.prices.usd, let value = Double(usd) {
                return (card, value)
            }
            if let eur = card.prices.eur, let value = Double(eur) {
                return (card, value)
            }
            return nil
        }
    }
}
