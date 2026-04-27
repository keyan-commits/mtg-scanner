import Testing
import Foundation
@testable import MTGCardScanner

@Suite("Collection Value Calculation Tests")
struct CollectionValueTests {

    // MARK: - Helpers

    /// Replicates the sell sheet value calculation from CollectionScreen.exportSellSheet()
    private static func calculateTotalValue(
        quantity: Int,
        foilQuantity: Int,
        currentValueUSD: Double?,
        currentValueFoilUSD: Double?
    ) -> Double {
        let currentUSD = currentValueUSD ?? 0
        let foilUSD = currentValueFoilUSD ?? currentUSD
        let nonFoilCount = quantity - foilQuantity
        return currentUSD * Double(nonFoilCount) + foilUSD * Double(foilQuantity)
    }

    private static func calculatePnL(totalValue: Double, purchasePrice: Double?) -> Double? {
        guard let purchase = purchasePrice, purchase > 0 else { return nil }
        return totalValue - purchase
    }

    // MARK: - Non-Foil Only

    @Test("All non-foil copies use non-foil price")
    func allNonFoil() {
        let value = Self.calculateTotalValue(
            quantity: 4, foilQuantity: 0,
            currentValueUSD: 10.0, currentValueFoilUSD: 15.0
        )
        #expect(value == 40.0)
    }

    // MARK: - All Foil

    @Test("All foil copies use foil price")
    func allFoil() {
        let value = Self.calculateTotalValue(
            quantity: 2, foilQuantity: 2,
            currentValueUSD: 10.0, currentValueFoilUSD: 25.0
        )
        #expect(value == 50.0)
    }

    // MARK: - Mixed

    @Test("Mixed foil and non-foil calculates correctly")
    func mixedFoilNonFoil() {
        let value = Self.calculateTotalValue(
            quantity: 4, foilQuantity: 1,
            currentValueUSD: 10.0, currentValueFoilUSD: 20.0
        )
        // 3 non-foil × $10 + 1 foil × $20 = $50
        #expect(value == 50.0)
    }

    // MARK: - Foil Price Fallback

    @Test("Falls back to non-foil price when foil price is nil")
    func foilPriceFallback() {
        let value = Self.calculateTotalValue(
            quantity: 2, foilQuantity: 1,
            currentValueUSD: 10.0, currentValueFoilUSD: nil
        )
        // 1 non-foil × $10 + 1 foil × $10 (fallback) = $20
        #expect(value == 20.0)
    }

    // MARK: - Nil Prices

    @Test("Nil current value treats as zero")
    func nilCurrentValue() {
        let value = Self.calculateTotalValue(
            quantity: 4, foilQuantity: 0,
            currentValueUSD: nil, currentValueFoilUSD: nil
        )
        #expect(value == 0.0)
    }

    // MARK: - Zero Quantity

    @Test("Zero quantity returns zero value")
    func zeroQuantity() {
        let value = Self.calculateTotalValue(
            quantity: 0, foilQuantity: 0,
            currentValueUSD: 50.0, currentValueFoilUSD: 75.0
        )
        #expect(value == 0.0)
    }

    // MARK: - P&L Calculations

    @Test("Positive P&L when value exceeds purchase price")
    func positivePnL() {
        let pnl = Self.calculatePnL(totalValue: 50.0, purchasePrice: 30.0)
        #expect(pnl == 20.0)
    }

    @Test("Negative P&L when value below purchase price")
    func negativePnL() {
        let pnl = Self.calculatePnL(totalValue: 20.0, purchasePrice: 50.0)
        #expect(pnl == -30.0)
    }

    @Test("Nil P&L when no purchase price")
    func nilPurchasePrice() {
        let pnl = Self.calculatePnL(totalValue: 50.0, purchasePrice: nil)
        #expect(pnl == nil)
    }

    @Test("Nil P&L when purchase price is zero")
    func zeroPurchasePrice() {
        let pnl = Self.calculatePnL(totalValue: 50.0, purchasePrice: 0)
        #expect(pnl == nil)
    }

    @Test("Zero P&L when value equals purchase price")
    func zeroPnL() {
        let pnl = Self.calculatePnL(totalValue: 50.0, purchasePrice: 50.0)
        #expect(pnl == 0.0)
    }
}
