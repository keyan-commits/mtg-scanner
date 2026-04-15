import Foundation

/// Shared formatting helpers used across the deck/order/shopping screens.
/// Centralized so we don't have 5 slightly-different `formatPrice`/`formatDate`
/// implementations drifting apart.

enum MoneyFormat {
    /// Whole-number for integer-like prices, otherwise 2 decimals.
    /// Used everywhere prices are displayed.
    static func compact(_ price: Double) -> String {
        if price.rounded() == price { return String(Int(price)) }
        return String(format: "%.2f", price)
    }

    /// Compact form, but uses no decimals for ≥100 values
    /// (used in the shopping list summary where big totals are common).
    static func compactLarge(_ price: Double) -> String {
        if price >= 100 { return String(format: "%.0f", price) }
        return String(format: "%.2f", price)
    }
}

/// Renders a multi-currency totals dictionary into a single line.
/// e.g. ["PHP": 4770, "USD": 50] → "PHP 4770 + USD 50"
enum CurrencyTotals {
    static func format(_ totals: [String: Double]) -> String? {
        guard !totals.isEmpty else { return nil }
        let parts = totals
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \(MoneyFormat.compact($0.value))" }
        return parts.joined(separator: " + ")
    }
}

enum ShortDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// "Mar 25, 2026" — used everywhere a short, human-readable date is shown.
    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
