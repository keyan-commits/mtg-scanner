import Foundation

struct CardPrices: Equatable, Sendable {
    let usd: String?
    let usdFoil: String?
    let eur: String?
    let eurFoil: String?
    let tix: String?

    var formattedPrice: String? {
        if let usd {
            return "$\(usd)"
        }
        if let usdFoil {
            return "$\(usdFoil) (foil)"
        }
        return nil
    }
}
