import Testing
import Foundation
@testable import MTGCardScanner

@Suite("Formatters Tests")
struct FormattersTests {

    // MARK: - MoneyFormat.compact

    @Test("compact: whole number shows no decimals")
    func compactWholeNumber() {
        #expect(MoneyFormat.compact(5.0) == "5")
    }

    @Test("compact: fractional shows 2 decimals")
    func compactFractional() {
        #expect(MoneyFormat.compact(5.5) == "5.50")
    }

    @Test("compact: precise decimal shows 2 decimals")
    func compactPrecise() {
        #expect(MoneyFormat.compact(12.99) == "12.99")
    }

    @Test("compact: zero shows as 0")
    func compactZero() {
        #expect(MoneyFormat.compact(0.0) == "0")
    }

    @Test("compact: large whole number")
    func compactLargeWhole() {
        #expect(MoneyFormat.compact(1000.0) == "1000")
    }

    // MARK: - MoneyFormat.compactLarge

    @Test("compactLarge: >= 100 uses no decimals")
    func compactLargeOver100() {
        #expect(MoneyFormat.compactLarge(150.75) == "151")
    }

    @Test("compactLarge: < 100 uses 2 decimals")
    func compactLargeUnder100() {
        #expect(MoneyFormat.compactLarge(99.99) == "99.99")
    }

    @Test("compactLarge: exactly 100 uses no decimals")
    func compactLargeExact100() {
        #expect(MoneyFormat.compactLarge(100.0) == "100")
    }

    // MARK: - CurrencyTotals.format

    @Test("format: single currency")
    func currencyTotalsSingle() {
        let result = CurrencyTotals.format(["USD": 50.0])
        #expect(result == "USD 50")
    }

    @Test("format: multiple currencies sorted by code")
    func currencyTotalsMultiple() {
        let result = CurrencyTotals.format(["USD": 50.0, "PHP": 4770.0])
        #expect(result == "PHP 4770 + USD 50")
    }

    @Test("format: empty returns nil")
    func currencyTotalsEmpty() {
        #expect(CurrencyTotals.format([:]) == nil)
    }

    // MARK: - ShortDate.format

    @Test("format: produces MMM d, yyyy")
    func shortDateFormat() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 25
        let date = Calendar.current.date(from: components)!
        let result = ShortDate.format(date)
        #expect(result == "Mar 25, 2026")
    }
}
