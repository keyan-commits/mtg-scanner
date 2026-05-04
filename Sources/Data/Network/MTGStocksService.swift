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

    // MARK: - Cache Size Limits

    private let maxIDCacheSize = 500
    private let maxDetailCacheSize = 200
    private let maxHistoryCacheSize = 200

    /// Card name → MTGStocks print ID (persists for the process lifetime).
    private var idCache: [String: Int] = [:]
    /// Print ID → card detail (24h TTL). `isFoilOnly` is part of the
    /// cached value because it changes vendor-price selection — same
    /// print id with a different foil-only flag must re-parse.
    private var detailCache: [Int: (detail: MTGStocksCard, fetchedAt: Date, isFoilOnly: Bool)] = [:]
    /// Print ID → price history (24h TTL).
    private var historyCache: [Int: (history: MTGStocksPriceHistory, fetchedAt: Date)] = [:]
    /// Interests cache (1h TTL). Backed by `interestsDiskCache` so the TTL
    /// survives app restarts — without this, every cold launch re-fetches
    /// because the in-memory value is empty.
    private var interestsCache: MTGStocksInterestsDiskCache.Blob?
    private let interestsDiskCache: MTGStocksInterestsDiskCache

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.interestsDiskCache = MTGStocksInterestsDiskCache()
        self.interestsCache = self.interestsDiskCache.load()
    }

    // MARK: - Public API

    /// Search for a card by name and return its MTGStocks print ID.
    /// When setCode and collectorNumber are provided, matches the exact
    /// printing from the card's `sets` array on MTGStocks.
    ///
    /// `promoTypes` is the Scryfall `promo_types` array — required to
    /// disambiguate multi-year promo buckets (FNM, Judge, Prerelease,
    /// Buy-A-Box, WPN/Gateway, Release/Launch) where MTGStocks reports
    /// an empty/null `abbreviation`.
    func lookupID(
        cardName: String,
        setCode: String? = nil,
        collectorNumber: String? = nil,
        promoTypes: [String] = []
    ) async -> Int? {
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
        if let setCode,
           let detailData = await fetch("/prints/\(cardID)"),
           let json = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
           let sets = json["sets"] as? [[String: Any]],
           let printID = MTGStocksService.selectPrintID(
               from: sets,
               cardName: cardName,
               scryfallSetCode: setCode,
               collectorNumber: collectorNumber,
               promoTypes: promoTypes
           ) {
            evictIDCacheIfNeeded()
            idCache[cacheKey] = printID
            return printID
        }

        // No set match — use the card-level default
        evictIDCacheIfNeeded()
        idCache[cacheKey] = cardID
        return cardID
    }

    /// Pure printing-selection logic — given a parsed MTGStocks `sets`
    /// array and a Scryfall (setCode, collectorNumber, promoTypes),
    /// returns the matching MTGStocks print id. Separated from
    /// `lookupID` so it can be unit-tested without mocking the network.
    ///
    /// Match priority:
    /// 1. Bucket match: if Scryfall maps to a known MTGStocks `set_id`
    ///    (FNM/Judge/Prerelease/Buy-A-Box/WPN/Release/The List), match
    ///    by `set_id` + collector number. The List is name-only.
    /// 2. Abbreviation/icon_class match: covers normal expansions where
    ///    Scryfall and MTGStocks codes agree (LRW=LRW, MMA=MMA, …).
    ///
    /// Returns nil when neither path produces an exact match — caller
    /// falls back to the card-level default print id. There is
    /// intentionally no "first printing in set" silent fallback: that's
    /// what was returning the wrong print before.
    static func selectPrintID(
        from sets: [[String: Any]],
        cardName: String,
        scryfallSetCode: String,
        collectorNumber: String?,
        promoTypes: [String]
    ) -> Int? {
        // 1. Bucket-based match by numeric set_id
        if let bucketSetID = MTGStocksSetMapper.mtgStocksSetID(
            scryfallCode: scryfallSetCode, promoTypes: promoTypes
        ) {
            let nameOnly = MTGStocksSetMapper.usesNameOnlyMatch(scryfallCode: scryfallSetCode)
            let lowerName = cardName.lowercased()
            if let printing = sets.first(where: { entry in
                guard (entry["set_id"] as? Int) == bucketSetID else { return false }
                if nameOnly {
                    let entryName = (entry["name"] as? String)?.lowercased()
                    return entryName == lowerName
                }
                guard let collectorNumber else { return false }
                let cn = entry["collector_number"] as? Int
                return cn.map(String.init) == collectorNumber
            }), let printID = printing["id"] as? Int {
                return printID
            }
        }

        // 2. Abbreviation / icon_class match (normal expansions)
        if let collectorNumber {
            let lowerSet = scryfallSetCode.lowercased()
            if let printing = sets.first(where: { entry in
                let abbr = (entry["abbreviation"] as? String)?.lowercased()
                let icon = (entry["icon_class"] as? String)?.lowercased()
                let cn = entry["collector_number"] as? Int
                return (abbr == lowerSet || icon == lowerSet)
                    && cn.map(String.init) == collectorNumber
            }), let printID = printing["id"] as? Int {
                return printID
            }
        }

        return nil
    }

    /// Fetch full card detail (multi-vendor prices, ATH/ATL, all printings).
    /// Pass `isFoilOnly: true` when the printing has no nonfoil variant
    /// — vendor-price selection prefers the foil aggregate over `avg`.
    func fetchCard(id: Int, isFoilOnly: Bool = false) async -> MTGStocksCard? {
        if let cached = detailCache[id],
           cached.isFoilOnly == isFoilOnly,
           Date().timeIntervalSince(cached.fetchedAt) < 86400 {
            return cached.detail
        }

        guard let data = await fetch("/prints/\(id)"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let card = MTGStocksCard.from(json: json, isFoilOnly: isFoilOnly) else { return nil }

        evictDetailCacheIfNeeded()
        detailCache[id] = (card, Date(), isFoilOnly)
        return card
    }

    /// Fetch price history for a card (all-time data points).
    func fetchPriceHistory(id: Int) async -> MTGStocksPriceHistory? {
        if let cached = historyCache[id], Date().timeIntervalSince(cached.fetchedAt) < 86400 {
            return cached.history
        }

        guard let data = await fetch("/prints/\(id)/prices") else { return nil }
        guard let history = try? JSONDecoder().decode(MTGStocksPriceHistory.self, from: data) else { return nil }

        evictHistoryCacheIfNeeded()
        historyCache[id] = (history, Date())
        return history
    }

    /// Returns the persisted interests cache without firing a network call.
    /// Lets the home screen show stale data immediately while a background
    /// refresh runs — without this, every cold launch blocks on the network.
    func cachedInterests() -> (entries: [MTGStocksInterest], fetchedAt: Date)? {
        guard let blob = interestsCache else { return nil }
        return (blob.entries, blob.fetchedAt)
    }

    /// Fetch today's trending cards (biggest price movers).
    func fetchInterests() async -> [MTGStocksInterest] {
        if let cached = interestsCache, Date().timeIntervalSince(cached.fetchedAt) < 3600 {
            return cached.entries
        }

        guard let data = await fetch("/interests/average/regular"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawInterests = json["interests"] as? [[String: Any]] else { return [] }

        // Filter to meaningful movers:
        // - Tournament-legal cards only (no Art Cards, tokens, etc.)
        // - Current price >= $2, previous price >= $1 (skip penny cards)
        // - Cap percentage at 500% to filter data glitches
        let interests = rawInterests.compactMap { entry -> MTGStocksInterest? in
            guard let printObj = entry["print"] as? [String: Any],
                  let id = printObj["id"] as? Int,
                  let name = printObj["name"] as? String else { return nil }
            // Skip non-tournament cards (art cards, tokens, etc.)
            let isTournamentLegal = printObj["tournamentLegal"] as? Bool ?? false
            guard isTournamentLegal else { return nil }
            // Skip art series, tokens, and special sets
            let setType = printObj["set_type"] as? String ?? ""
            let skipSetTypes: Set<String> = [
                "art_series", "token", "memorabilia", "minigame", "vanguard",
                "funny", "treasure_chest"
            ]
            guard !skipSetTypes.contains(setType) else { return nil }
            // Skip non-standard printings
            let setNameStr = printObj["set_name"] as? String ?? ""
            let excludedSubstrings = ["Foreign Black Border", "Foreign White Border",
                                      "Collectors' Edition", "International Edition",
                                      "30th Anniversary", "World Championship"]
            guard !excludedSubstrings.contains(where: { setNameStr.contains($0) }) else { return nil }
            // Skip if name contains "Art Card"
            guard !name.contains("Art Card") else { return nil }
            let currentPrice = entry["present_price"] as? Double
            let previousPrice = entry["past_price"] as? Double
            let pct = entry["percentage"] as? Double
            guard let current = currentPrice, current >= 2.0,
                  let previous = previousPrice, previous >= 1.0 else { return nil }
            // Cap at 500% to filter data glitches
            guard let percent = pct, abs(percent) <= 500 else { return nil }
            let setName = printObj["set_name"] as? String
            let setCode = printObj["set_code"] as? String
            return MTGStocksInterest(
                id: id, name: name, setName: setName, setCode: setCode,
                currentPrice: current, previousPrice: previous,
                percentageChange: percent
            )
        }

        // Deduplicate by card name, keep highest absolute change
        var bestByName: [String: MTGStocksInterest] = [:]
        for interest in interests {
            let key = interest.name.lowercased()
            if let existing = bestByName[key] {
                let existingDelta = abs((existing.currentPrice ?? 0) - (existing.previousPrice ?? 0))
                let newDelta = abs((interest.currentPrice ?? 0) - (interest.previousPrice ?? 0))
                if newDelta > existingDelta { bestByName[key] = interest }
            } else {
                bestByName[key] = interest
            }
        }

        let sorted = bestByName.values
            .sorted { abs($0.percentageChange ?? 0) > abs($1.percentageChange ?? 0) }

        let blob = MTGStocksInterestsDiskCache.Blob(entries: sorted, fetchedAt: Date())
        interestsCache = blob
        interestsDiskCache.save(blob)
        return sorted
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

    // MARK: - Cache Eviction

    /// Evict a random entry from idCache if at capacity (no timestamps to sort by).
    private func evictIDCacheIfNeeded() {
        guard idCache.count >= maxIDCacheSize else { return }
        if let key = idCache.keys.randomElement() {
            idCache.removeValue(forKey: key)
        }
    }

    /// Evict the oldest entry from detailCache if at capacity.
    private func evictDetailCacheIfNeeded() {
        guard detailCache.count >= maxDetailCacheSize else { return }
        if let oldest = detailCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt }) {
            detailCache.removeValue(forKey: oldest.key)
        }
    }

    /// Evict the oldest entry from historyCache if at capacity.
    private func evictHistoryCacheIfNeeded() {
        guard historyCache.count >= maxHistoryCacheSize else { return }
        if let oldest = historyCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt }) {
            historyCache.removeValue(forKey: oldest.key)
        }
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
    ///
    /// `isFoilOnly` flips the vendor-price preference order: for foil-only
    /// printings, the foil aggregate is preferred over `avg` (which on
    /// some prints aggregates non-foil sales of an unrelated reprint and
    /// is the wrong number to surface).
    static func from(json: [String: Any], isFoilOnly: Bool = false) -> MTGStocksCard? {
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
            let avg = (latest["avg"] as? Double).flatMap { $0 > 0 ? $0 : nil }
            let foil = (latest["foil"] as? Double).flatMap { $0 > 0 ? $0 : nil }
            let low = (latest["low"] as? Double).flatMap { $0 > 0 ? $0 : nil }

            if isFoilOnly, let foil {
                vendors.append(VendorPrice(vendor: label, price: foil, isFoil: true, url: url))
            } else if let avg {
                vendors.append(VendorPrice(vendor: label, price: avg, isFoil: false, url: url))
            } else if let foil {
                vendors.append(VendorPrice(vendor: label, price: foil, isFoil: true, url: url))
            } else if let low {
                vendors.append(VendorPrice(vendor: label, price: low, isFoil: false, url: url))
            }
        }

        // Extract real TCGPlayer Low/Market/High tier prices
        let tcgLatest = (json["tcgplayer"] as? [String: Any])?["latestPrice"] as? [String: Any]
        let tcgLow = tcgLatest?["low"] as? Double
        let tcgHigh = tcgLatest?["high"] as? Double
        // Market: prefer `avg` (listings average) over `market` (TCGPlayer's
        // algorithmic median) so the Range bar's middle tier matches the
        // value the chart and Compare Prices vendor row already use.
        // For mid-rally cards (Necropotence 2026-05) the two diverge by
        // double-digit %, and showing "Market $49" beside chart-endpoint
        // "$63" reads as a bug. Foil-only fallbacks remain.
        let tcgMarket = (tcgLatest?["avg"] as? Double)
            ?? (tcgLatest?["market"] as? Double)
            ?? (tcgLatest?["foil"] as? Double)
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
    /// `preferFoil` flips the precedence to foil/marketFoil first — pass
    /// true for foil-only printings (FNM, Secret Lair foils, Magic Online
    /// promos) so the chart reflects the actual finish that exists.
    func averagePrices(preferFoil: Bool = false) -> [(date: Date, price: Double)] {
        let source: [[Double]]
        if preferFoil {
            source = foil ?? marketFoil ?? avg ?? market ?? []
        } else {
            source = avg ?? market ?? foil ?? marketFoil ?? []
        }
        return source.compactMap { point in
            guard point.count >= 2 else { return nil }
            return (Date(timeIntervalSince1970: point[0] / 1000), point[1])
        }
    }
}

struct MTGStocksInterest: Sendable, Codable, Equatable {
    let id: Int
    let name: String
    let setName: String?
    let setCode: String?
    let currentPrice: Double?
    let previousPrice: Double?
    let percentageChange: Double?
}
