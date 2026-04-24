import Foundation

/// Client for the MTGStocks API. Provides price history, multi-vendor
/// prices, all-time highs/lows, and trending card data that Scryfall
/// does not offer.
///
/// The API is undocumented and requires a browser-like User-Agent.
/// All responses are cached aggressively to minimize requests.
actor MTGStocksService {

    static let shared = MTGStocksService()

    private let baseURL = "https://api.mtgstocks.com"
    private let session: URLSession

    /// Card name → MTGStocks print ID (persists for the process lifetime).
    private var idCache: [String: Int] = [:]
    /// Print ID → card detail (24h TTL).
    private var detailCache: [Int: (detail: MTGStocksCard, fetchedAt: Date)] = [:]
    /// Print ID → price history (24h TTL).
    private var historyCache: [Int: (history: MTGStocksPriceHistory, fetchedAt: Date)] = [:]
    /// Interests cache (1h TTL).
    private var interestsCache: (entries: [MTGStocksInterest], fetchedAt: Date)?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Search for a card by name and return its MTGStocks print ID.
    func lookupID(cardName: String) async -> Int? {
        if let cached = idCache[cardName.lowercased()] { return cached }

        let encoded = cardName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cardName
        guard let data = await fetch("/search/autocomplete/\(encoded)") else { return nil }

        struct SearchResult: Decodable {
            let id: Int
            let name: String
        }

        guard let results = try? JSONDecoder().decode([SearchResult].self, from: data) else { return nil }

        // Prefer exact match, fall back to first result
        let match = results.first(where: { $0.name.lowercased() == cardName.lowercased() })
            ?? results.first
        guard let id = match?.id else { return nil }

        idCache[cardName.lowercased()] = id
        return id
    }

    /// Fetch full card detail (multi-vendor prices, ATH/ATL, all printings).
    func fetchCard(id: Int) async -> MTGStocksCard? {
        if let cached = detailCache[id], Date().timeIntervalSince(cached.fetchedAt) < 86400 {
            return cached.detail
        }

        guard let data = await fetch("/prints/\(id)") else { return nil }
        guard let card = try? JSONDecoder().decode(MTGStocksCard.self, from: data) else { return nil }

        detailCache[id] = (card, Date())
        return card
    }

    /// Fetch price history for a card (all-time data points).
    func fetchPriceHistory(id: Int) async -> MTGStocksPriceHistory? {
        if let cached = historyCache[id], Date().timeIntervalSince(cached.fetchedAt) < 86400 {
            return cached.history
        }

        guard let data = await fetch("/prints/\(id)/prices") else { return nil }
        guard let history = try? JSONDecoder().decode(MTGStocksPriceHistory.self, from: data) else { return nil }

        historyCache[id] = (history, Date())
        return history
    }

    /// Fetch today's trending cards (biggest price movers).
    func fetchInterests() async -> [MTGStocksInterest] {
        if let cached = interestsCache, Date().timeIntervalSince(cached.fetchedAt) < 3600 {
            return cached.entries
        }

        guard let data = await fetch("/interests/average/regular") else { return [] }
        guard let interests = try? JSONDecoder().decode([MTGStocksInterest].self, from: data) else { return [] }

        interestsCache = (interests, Date())
        return interests
    }

    /// Convenience: look up a card by name and return its price history.
    func fetchPriceHistory(cardName: String) async -> MTGStocksPriceHistory? {
        guard let id = await lookupID(cardName: cardName) else { return nil }
        return await fetchPriceHistory(id: id)
    }

    /// Convenience: look up a card by name and return its detail.
    func fetchCard(cardName: String) async -> MTGStocksCard? {
        guard let id = await lookupID(cardName: cardName) else { return nil }
        return await fetchCard(id: id)
    }

    /// Returns the MTGStocks web URL for a card (for "View on MTGStocks" links).
    func webURL(id: Int) -> URL? {
        URL(string: "https://www.mtgstocks.com/prints/\(id)")
    }

    // MARK: - Network

    private func fetch(_ path: String) async -> Data? {
        guard let url = URL(string: "\(baseURL)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }
}

// MARK: - Response Models

struct MTGStocksCard: Decodable {
    let id: Int
    let name: String
    let setName: String?
    let allTimeHigh: Double?
    let allTimeLow: Double?
    let allTimeHighDate: String?
    let allTimeLowDate: String?
    let latestPrice: Double?
    let latestPriceFoil: Double?
    let cardKingdomPrice: Double?
    let cardKingdomPriceFoil: Double?
    let cardMarketPrice: Double?
    let cardMarketPriceFoil: Double?

    enum CodingKeys: String, CodingKey {
        case id, name
        case setName = "set_name"
        case allTimeHigh = "all_time_high"
        case allTimeLow = "all_time_low"
        case allTimeHighDate = "all_time_high_date"
        case allTimeLowDate = "all_time_low_date"
        case latestPrice = "latest_price"
        case latestPriceFoil = "latest_price_foil"
        case cardKingdomPrice = "card_kingdom_price"
        case cardKingdomPriceFoil = "card_kingdom_price_foil"
        case cardMarketPrice = "card_market_price"
        case cardMarketPriceFoil = "card_market_price_foil"
    }
}

struct MTGStocksPriceHistory: Decodable {
    /// Each entry is [timestamp_ms, price_usd].
    let low: [[Double]]?
    let avg: [[Double]]?
    let high: [[Double]]?
    let foil: [[Double]]?
    let market: [[Double]]?
    let marketFoil: [[Double]]?

    enum CodingKeys: String, CodingKey {
        case low = "LOW"
        case avg = "AVG"
        case high = "HIGH"
        case foil = "FOIL"
        case market = "MARKET"
        case marketFoil = "MARKET_FOIL"
    }

    /// Returns the average price data points as (date, price) tuples.
    var averagePrices: [(date: Date, price: Double)] {
        (avg ?? market ?? []).compactMap { point in
            guard point.count >= 2 else { return nil }
            return (Date(timeIntervalSince1970: point[0] / 1000), point[1])
        }
    }
}

struct MTGStocksInterest: Decodable {
    let id: Int
    let name: String
    let setName: String?
    let currentPrice: Double?
    let previousPrice: Double?
    let percentageChange: Double?

    enum CodingKeys: String, CodingKey {
        case id, name
        case setName = "set_name"
        case currentPrice = "current_price"
        case previousPrice = "previous_price"
        case percentageChange = "percentage"
    }
}
