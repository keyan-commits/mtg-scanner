import Testing
import Foundation
@testable import MTGCardScanner

@Suite("CollectionPricing — foil-aware row math")
struct CollectionPricingTests {

    // MARK: - lineValueUSD

    @Test("All-nonfoil row uses nonfoil price × quantity")
    func allNonfoilUsesNonfoilPrice() {
        let line = CollectionPricing.lineValueUSD(
            quantity: 4,
            foilQuantity: 0,
            nonfoilPriceUSD: 1.50,
            foilPriceUSD: 14.02
        )
        #expect(line == 6.00)
    }

    @Test("All-foil row uses foil price × quantity (regression: was using nonfoil)")
    func allFoilUsesFoilPrice() {
        // Tree of Tales scenario: 1 foil copy. Was rendering ₱103.50 (nonfoil
        // $1.59 × ~65) instead of foil price $14.02. After fix, uses foil.
        let line = CollectionPricing.lineValueUSD(
            quantity: 1,
            foilQuantity: 1,
            nonfoilPriceUSD: 1.59,
            foilPriceUSD: 14.02
        )
        #expect(line == 14.02)
    }

    @Test("Mixed copies sum each finish at its own price")
    func mixedRowSumsFoilAndNonfoil() {
        // 4 copies, 2 of them foil → 2 × nonfoil + 2 × foil
        let line = CollectionPricing.lineValueUSD(
            quantity: 4,
            foilQuantity: 2,
            nonfoilPriceUSD: 2.00,
            foilPriceUSD: 10.00
        )
        #expect(line == 24.00)
    }

    @Test("Foil-only printing (no nonfoil price) still values foil copies")
    func foilOnlyPrintingValuesFoilCopies() {
        // Spellstutter Sprite FNM scenario: no nonfoil printing exists in
        // Scryfall, so nonfoilPriceUSD is nil. A row of 4 foil copies must
        // still surface a price — was rendering blank before the fix.
        let line = CollectionPricing.lineValueUSD(
            quantity: 4,
            foilQuantity: 4,
            nonfoilPriceUSD: nil,
            foilPriceUSD: 8.50
        )
        #expect(line == 34.00)
    }

    @Test("Nonfoil-only printing values nonfoil copies even when foil price is missing")
    func nonfoilOnlyPrintingValuesNonfoilCopies() {
        let line = CollectionPricing.lineValueUSD(
            quantity: 3,
            foilQuantity: 0,
            nonfoilPriceUSD: 0.25,
            foilPriceUSD: nil
        )
        #expect(line == 0.75)
    }

    @Test("Mixed copies fall back to whichever finish has a price when one is missing")
    func mixedFallsBackWhenOneFinishMissing() {
        // 4 copies, 2 foil — but only the foil price is known. Each copy
        // (foil or nonfoil) is valued at the foil price rather than dropping
        // the row to nil. Better approximation than zero when only one
        // finish has price data.
        let line = CollectionPricing.lineValueUSD(
            quantity: 4,
            foilQuantity: 2,
            nonfoilPriceUSD: nil,
            foilPriceUSD: 5.00
        )
        #expect(line == 20.00)
    }

    @Test("Both prices nil returns nil (no row value)")
    func bothPricesNilReturnsNil() {
        let line = CollectionPricing.lineValueUSD(
            quantity: 2,
            foilQuantity: 1,
            nonfoilPriceUSD: nil,
            foilPriceUSD: nil
        )
        #expect(line == nil)
    }

    @Test("Zero quantity returns nil")
    func zeroQuantityReturnsNil() {
        let line = CollectionPricing.lineValueUSD(
            quantity: 0,
            foilQuantity: 0,
            nonfoilPriceUSD: 1.00,
            foilPriceUSD: 10.00
        )
        #expect(line == nil)
    }

    @Test("foilQuantity exceeding quantity is clamped to quantity (defensive)")
    func foilQuantityClampedToTotal() {
        // Old data may have foilQuantity > quantity from the pre-repair
        // schema. Treat the excess as foil (don't double-count or go negative).
        let line = CollectionPricing.lineValueUSD(
            quantity: 2,
            foilQuantity: 5,
            nonfoilPriceUSD: 1.00,
            foilPriceUSD: 10.00
        )
        #expect(line == 20.00)
    }

    // MARK: - averageUnitPriceUSD

    @Test("Average unit price for all-foil row is the foil price")
    func averageUnitForAllFoil() {
        let unit = CollectionPricing.averageUnitPriceUSD(
            quantity: 4,
            foilQuantity: 4,
            nonfoilPriceUSD: 2.00,
            foilPriceUSD: 8.00
        )
        #expect(unit == 8.00)
    }

    @Test("Average unit price for mixed row is the weighted average")
    func averageUnitForMixed() {
        // 2 nonfoil @ $1, 2 foil @ $9 → total $20 / 4 copies = $5/ea
        let unit = CollectionPricing.averageUnitPriceUSD(
            quantity: 4,
            foilQuantity: 2,
            nonfoilPriceUSD: 1.00,
            foilPriceUSD: 9.00
        )
        #expect(unit == 5.00)
    }

    // MARK: - dominantUnitPriceUSD

    @Test("Dominant unit picks foil when row is all-foil")
    func dominantPicksFoilForAllFoil() {
        let dom = CollectionPricing.dominantUnitPriceUSD(
            quantity: 1,
            foilQuantity: 1,
            nonfoilPriceUSD: 1.59,
            foilPriceUSD: 14.02
        )
        #expect(dom == 14.02)
    }

    @Test("Dominant unit picks nonfoil when row is majority nonfoil")
    func dominantPicksNonfoilForMostlyNonfoil() {
        let dom = CollectionPricing.dominantUnitPriceUSD(
            quantity: 4,
            foilQuantity: 1,
            nonfoilPriceUSD: 1.00,
            foilPriceUSD: 10.00
        )
        #expect(dom == 1.00)
    }

    @Test("Dominant unit picks foil when row is foil-majority but mixed")
    func dominantPicksFoilForFoilMajority() {
        let dom = CollectionPricing.dominantUnitPriceUSD(
            quantity: 4,
            foilQuantity: 3,
            nonfoilPriceUSD: 1.00,
            foilPriceUSD: 10.00
        )
        #expect(dom == 10.00)
    }
}
