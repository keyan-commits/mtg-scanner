import Foundation

/// Fetches and caches USD-base exchange rates from Frankfurter
/// (https://www.frankfurter.app/) — a free, no-API-key currency rates
/// service backed by ECB data. Cached for 24 hours so we don't hammer
/// the endpoint on every screen open.
@MainActor
@Observable
final class CurrencyService {

    /// Latest fetched rates: `[currencyCode: rate]` where each rate is
    /// "how many <currency> equal 1 USD." USD itself is always 1.0.
    private(set) var rates: [String: Double] = [:]

    /// Last successful fetch timestamp (Unix seconds). 0 if never.
    private(set) var lastUpdated: Date?

    /// Singleton — there's no reason to have more than one.
    static let shared = CurrencyService()

    private let cacheKey = "currencyRates_v1"
    private let timestampKey = "currencyRatesTimestamp_v1"
    private let maxAge: TimeInterval = 24 * 60 * 60 // 24h

    private init() {
        loadCache()
    }

    /// Fetches new rates if the cache is older than 24 hours, otherwise
    /// no-ops. Safe to call from any screen's `.task`.
    func refreshIfStale() async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge, !rates.isEmpty {
            return
        }
        await fetch()
    }

    /// Forces a fresh fetch regardless of cache age.
    func refresh() async {
        await fetch()
    }

    /// Converts a USD amount into the target currency. Returns nil if
    /// the rate isn't available (e.g. unknown currency code or fetch
    /// failed and no cache exists).
    func convert(_ usd: Double, to currency: String) -> Double? {
        if currency == "USD" { return usd }
        guard let rate = rates[currency] else { return nil }
        return usd * rate
    }

    // MARK: - Private

    private func fetch() async {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Response: Decodable {
                let rates: [String: Double]
            }
            let response = try JSONDecoder().decode(Response.self, from: data)
            var combined = response.rates
            combined["USD"] = 1.0  // Frankfurter omits the base currency
            self.rates = combined
            self.lastUpdated = Date()
            saveCache()
        } catch {
            // Silent failure — keep stale cache. The currency feature is
            // optional UX, never block the screen on it.
        }
    }

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.rates = decoded
        }
        let ts = UserDefaults.standard.double(forKey: timestampKey)
        if ts > 0 {
            self.lastUpdated = Date(timeIntervalSince1970: ts)
        }
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(rates) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        if let lastUpdated {
            UserDefaults.standard.set(lastUpdated.timeIntervalSince1970, forKey: timestampKey)
        }
    }
}

// MARK: - User preference

/// User-selected display currency for collection / deck spend / value
/// rendering. Persisted via UserDefaults so it survives launches.
enum LocalCurrency {
    private static let key = "preferredDisplayCurrency_v1"

    /// Tuple of `(ISO 4217 code, display name, currency symbol)`.
    static let supported: [(code: String, name: String, symbol: String)] = [
        ("USD", "US Dollar", "$"),
        ("EUR", "Euro", "€"),
        ("GBP", "British Pound", "£"),
        ("PHP", "Philippine Peso", "₱"),
        ("JPY", "Japanese Yen", "¥"),
        ("CAD", "Canadian Dollar", "C$"),
        ("AUD", "Australian Dollar", "A$"),
        ("INR", "Indian Rupee", "₹"),
        ("MXN", "Mexican Peso", "MX$"),
        ("BRL", "Brazilian Real", "R$"),
        ("SGD", "Singapore Dollar", "S$"),
        ("HKD", "Hong Kong Dollar", "HK$"),
        ("KRW", "South Korean Won", "₩"),
        ("CNY", "Chinese Yuan", "¥"),
    ]

    static var current: String {
        get { UserDefaults.standard.string(forKey: key) ?? "USD" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func symbol(for code: String) -> String {
        supported.first(where: { $0.code == code })?.symbol ?? code
    }

    static func name(for code: String) -> String {
        supported.first(where: { $0.code == code })?.name ?? code
    }

    /// Format an already-converted amount with the appropriate symbol +
    /// digit grouping. JPY/KRW have no decimals; everything else uses 2.
    static func format(_ amount: Double, currency: String) -> String {
        let symbol = symbol(for: currency)
        let zeroDecimal: Set<String> = ["JPY", "KRW"]
        let digits = zeroDecimal.contains(currency) ? 0 : 2
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.usesGroupingSeparator = true
        let str = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(symbol)\(str)"
    }
}
