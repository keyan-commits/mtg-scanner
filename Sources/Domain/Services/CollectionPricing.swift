import Foundation

// Foil-aware money math for collection rows.
//
// A CollectionItem can hold a mix of foil and nonfoil copies of one
// printing. The display price has to honor that — a foil-only item
// must use the foil price, not the nonfoil. We had a regression where
// CollectionScreen was multiplying the nonfoil price by total quantity,
// so foil-only items showed nonfoil values (and printings without a
// nonfoil version showed nothing at all).
enum CollectionPricing {

    /// Total USD for the row: nonfoil_count × nonfoil_price + foil_count × foil_price.
    /// If only one finish has a price, both finishes fall back to it (better
    /// than showing zero). Returns nil only when both prices are missing.
    static func lineValueUSD(
        quantity: Int,
        foilQuantity: Int,
        nonfoilPriceUSD: Double?,
        foilPriceUSD: Double?
    ) -> Double? {
        let totalQty = max(0, quantity)
        guard totalQty > 0 else { return nil }
        let foilCount = min(max(0, foilQuantity), totalQty)
        let nonfoilCount = totalQty - foilCount
        let nonfoilPrice = nonfoilPriceUSD ?? foilPriceUSD
        let foilPrice = foilPriceUSD ?? nonfoilPriceUSD
        guard let np = nonfoilPrice, let fp = foilPrice else { return nil }
        return Double(nonfoilCount) * np + Double(foilCount) * fp
    }

    /// Average per-copy USD for "₱X ea" display. Weighted average across
    /// foil and nonfoil copies; for an all-one-finish row this is simply
    /// that finish's price.
    static func averageUnitPriceUSD(
        quantity: Int,
        foilQuantity: Int,
        nonfoilPriceUSD: Double?,
        foilPriceUSD: Double?
    ) -> Double? {
        let totalQty = max(0, quantity)
        guard totalQty > 0,
              let line = lineValueUSD(
                quantity: totalQty,
                foilQuantity: foilQuantity,
                nonfoilPriceUSD: nonfoilPriceUSD,
                foilPriceUSD: foilPriceUSD
              )
        else { return nil }
        return line / Double(totalQty)
    }

    /// The "current price for one copy" used to compare against
    /// `priceAtAddUSD`. Picks the foil price when the row is foil-majority.
    static func dominantUnitPriceUSD(
        quantity: Int,
        foilQuantity: Int,
        nonfoilPriceUSD: Double?,
        foilPriceUSD: Double?
    ) -> Double? {
        let totalQty = max(0, quantity)
        guard totalQty > 0 else { return nil }
        let foilCount = min(max(0, foilQuantity), totalQty)
        let isFoilMajority = foilCount * 2 > totalQty || (foilCount == totalQty)
        if isFoilMajority {
            return foilPriceUSD ?? nonfoilPriceUSD
        }
        return nonfoilPriceUSD ?? foilPriceUSD
    }
}
