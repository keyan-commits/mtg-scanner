import Foundation

struct CardPrices: Equatable, Sendable {
    let usd: String?
    let usdFoil: String?
    let eur: String?
    let eurFoil: String?
    let tix: String?
    /// Previous day's USD price (nil until first price refresh).
    let previousUsd: String?

    var formattedPrice: String? {
        if let usd {
            return "$\(usd)"
        }
        if let usdFoil {
            return "$\(usdFoil) (foil)"
        }
        return nil
    }

    /// 24-hour price change as a percentage. Nil if no previous data.
    var priceChangePercent: Double? {
        guard let current = usd.flatMap(Double.init),
              let previous = previousUsd.flatMap(Double.init),
              previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    /// 24-hour price change in USD. Nil if no previous data.
    var priceChangeUSD: Double? {
        guard let current = usd.flatMap(Double.init),
              let previous = previousUsd.flatMap(Double.init) else { return nil }
        return current - previous
    }
}
