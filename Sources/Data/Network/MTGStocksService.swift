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
    /// When setCode and collectorNumber are provided, matches the exact
    /// printing from the card's `sets` array on MTGStocks.
    func lookupID(cardName: String, setCode: String? = nil, collectorNumber: String? = nil) async -> Int? {
        let cacheKey = "\(cardName.lowercased())|\(setCode ?? "")|\(collectorNumber ?? "")"
        if let cached = idCache[cacheKey] { return cached }

        let encoded = cardName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cardName
        guard let data = await fetch("/search/autocomplete/\(encoded)") else { return nil }

        struct SearchResult: Decodable {
            let id: Int
            let name: String
        }

        guard let results = try? JSONDecoder().decode([SearchResult].self, from: data) else { return nil }

        // Find the card-level entry (exact name match or first result)
        let match = results.first(where: { $0.name.lowercased() == cardName.lowercased() })
            ?? results.first
        guard let cardID = match?.id else { return nil }

        // If set code provided, fetch the card detail to find the exact printing
        if let setCode, let collectorNumber,
           let detailData = await fetch("/prints/\(cardID)"),
           let json = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
           let sets = json["sets"] as? [[String: Any]] {
            let lowerSet = setCode.lowercased()
            // Match by set abbreviation/icon_class + collector number
            if let printing = sets.first(where: { entry in
                let abbr = (entry["abbreviation"] as? String)?.lowercased()
                let icon = (entry["icon_class"] as? String)?.lowercased()
                let cn = entry["collector_number"] as? Int
                let cnStr = cn.map(String.init)
                return (abbr == lowerSet || icon == lowerSet) && cnStr == collectorNumber
            }), let printID = printing["id"] as? Int {
                idCache[cacheKey] = printID
                return printID
            }
            // Fallback: match by set only (first printing in that set)
            if let printing = sets.first(where: { entry in
                let abbr = (entry["abbreviation"] as? String)?.lowercased()
                let icon = (entry["icon_class"] as? String)?.lowercased()
                return abbr == lowerSet || icon == lowerSet
            }), let printID = printing["id"] as? Int {
                idCache[cacheKey] = printID
                return printID
            }
        }

        // No set match — use the card-level default
        idCache[cacheKey] = cardID
        return cardID
    }

    /// Fetch full card detail (multi-vendor prices, ATH/ATL, all printings).
    func fetchCard(id: Int) async -> MTGStocksCard? {
        if let cached = detailCache[id], Date().timeIntervalSince(cached.fetchedAt) < 86400 {
            return cached.detail
        }

        guard let data = await fetch("/prints/\(id)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let card = MTGStocksCard.from(json: json) else { return nil }

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

struct MTGStocksCard {
    let id: Int
    let name: String
    let allTimeHigh: ATRecord?
    let allTimeLow: ATRecord?
    let vendorPrices: [VendorPrice]
    /// Real TCGPlayer tier prices (low/market/high) from MTGStocks.
    let tcgLow: Double?
    let tcgMarket: Double?
    let tcgHigh: Double?

    struct ATRecord {
        let avg: Double?
    }

    struct VendorPrice {
        let vendor: String
        let price: Double
        let isFoil: Bool
        let url: URL?
    }
}

extension MTGStocksCard {
    /// Parse from raw JSON since the vendor structures are irregular.
    static func from(json: [String: Any]) -> MTGStocksCard? {
        guard let id = json["id"] as? Int,
              let name = json["name"] as? String else { return nil }

        let ath: ATRecord? = (json["all_time_high"] as? [String: Any]).flatMap {
            ATRecord(avg: $0["avg"] as? Double)
        }
        let atl: ATRecord? = (json["all_time_low"] as? [String: Any]).flatMap {
            ATRecord(avg: $0["avg"] as? Double)
        }

        let vendorKeys: [(key: String, label: String)] = [
            ("tcgplayer", "TCGPlayer"),
            ("cardkingdom", "Card Kingdom"),
            ("starcitygames", "Star City Games"),
            ("cardmarket", "Cardmarket"),
            ("cardtrader", "CardTrader"),
            ("manapool", "ManaPool"),
        ]

        var vendors: [VendorPrice] = []
        for (key, label) in vendorKeys {
            guard let vendor = json[key] as? [String: Any],
                  let latest = vendor["latestPrice"] as? [String: Any] else { continue }
            let url = (vendor["url"] as? String).flatMap(URL.init(string:))
                   ?? (vendor["urlFoil"] as? String).flatMap(URL.init(string:))
            // Try avg first, then foil, then low
            if let avg = latest["avg"] as? Double, avg > 0 {
                vendors.append(VendorPrice(vendor: label, price: avg, isFoil: false, url: url))
            } else if let foil = latest["foil"] as? Double, foil > 0 {
                vendors.append(VendorPrice(vendor: label, price: foil, isFoil: true, url: url))
            } else if let low = latest["low"] as? Double, low > 0 {
                vendors.append(VendorPrice(vendor: label, price: low, isFoil: false, url: url))
            }
        }

        // Extract real TCGPlayer Low/Market/High tier prices
        let tcgLatest = (json["tcgplayer"] as? [String: Any])?["latestPrice"] as? [String: Any]
        let tcgLow = tcgLatest?["low"] as? Double
        let tcgHigh = tcgLatest?["high"] as? Double
        // Market: try regular first, then foil
        let tcgMarket = (tcgLatest?["market"] as? Double)
            ?? (tcgLatest?["market_foil"] as? Double)

        return MTGStocksCard(
            id: id, name: name,
            allTimeHigh: ath, allTimeLow: atl,
            vendorPrices: vendors,
            tcgLow: tcgLow, tcgMarket: tcgMarket, tcgHigh: tcgHigh
        )
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
        case low, avg, high, foil, market
        case marketFoil = "market_foil"
    }

    /// Returns price data points as (date, price) tuples.
    /// Tries avg → market → foil → marketFoil for foil-only printings.
    var averagePrices: [(date: Date, price: Double)] {
        let source = avg ?? market ?? foil ?? marketFoil ?? []
        return source.compactMap { point in
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
