import Foundation
import SwiftData

/// Downloads Scryfall bulk data and updates card prices in the local database.
/// Runs automatically daily (on app launch if >24h stale) and on-demand from Settings.
@Observable
@MainActor
final class PriceRefreshService {

    static var shared: PriceRefreshService?

    var isRefreshing = false
    var progress: Double = 0

    private let downloader: ScryfallBulkDataDownloader
    private let databaseManager: DatabaseManager

    private static let lastRefreshKey = "lastPriceRefresh"

    init(downloader: ScryfallBulkDataDownloader, databaseManager: DatabaseManager) {
        self.downloader = downloader
        self.databaseManager = databaseManager
    }

    var lastUpdated: Date? {
        let interval = UserDefaults.standard.double(forKey: Self.lastRefreshKey)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    var isStale: Bool {
        guard let last = lastUpdated else { return true }
        return Date().timeIntervalSince(last) > 24 * 60 * 60
    }

    /// Refreshes prices if last update was >24 hours ago.
    func refreshIfStale() async {
        guard isStale, !isRefreshing else { return }
        await refresh()
    }

    /// Downloads latest Scryfall data and updates prices for all cards.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        progress = 0
        defer { isRefreshing = false }

        do {
            print("[PriceRefresh] Downloading Scryfall bulk data…")
            let fileURL = try await downloader.downloadBulkData()
            progress = 0.3

            print("[PriceRefresh] Parsing JSON…")
            let data = try Data(contentsOf: fileURL)
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                print("[PriceRefresh] Invalid JSON")
                return
            }
            progress = 0.5

            print("[PriceRefresh] Updating \(jsonArray.count) card prices…")

            // Build price lookup from downloaded data: scryfallID → prices
            var priceLookup: [String: (usd: String?, usdFoil: String?, eur: String?, eurFoil: String?, tix: String?, reserved: Bool)] = [:]
            for json in jsonArray {
                guard let id = json["id"] as? String,
                      let prices = json["prices"] as? [String: Any?] else { continue }
                priceLookup[id] = (
                    usd: prices["usd"] as? String,
                    usdFoil: prices["usd_foil"] as? String,
                    eur: prices["eur"] as? String,
                    eurFoil: prices["eur_foil"] as? String,
                    tix: prices["tix"] as? String,
                    reserved: json["reserved"] as? Bool ?? false
                )
            }
            progress = 0.6

            // Run heavy DB updates on a background thread to avoid blocking UI
            let container = databaseManager.modelContainer
            let lookup = priceLookup
            let (updatedCount, collectionTotal) = try await Task.detached(priority: .utility) {
                let context = ModelContext(container)

                // Fetch all existing records and update prices in batches
                let descriptor = FetchDescriptor<CardRecord>()
                let records = try context.fetch(descriptor)
                var updated = 0

                for record in records {
                    if let prices = lookup[record.scryfallID] {
                        record.previousPriceUSD = record.priceUSD
                        record.priceUSD = prices.usd
                        record.priceUSDFoil = prices.usdFoil
                        record.priceEUR = prices.eur
                        record.priceEURFoil = prices.eurFoil
                        record.priceTix = prices.tix
                        record.isReserved = prices.reserved
                        updated += 1
                    }

                    if updated % 5000 == 0 && updated > 0 {
                        try context.save()
                    }
                }
                try context.save()

                // Update collection item values
                let collectionDescriptor = FetchDescriptor<CollectionItem>()
                let collectionItems = (try? context.fetch(collectionDescriptor)) ?? []
                for item in collectionItems {
                    if let prices = lookup[item.scryfallID] {
                        if let usdString = prices.usd, let usd = Double(usdString) {
                            item.currentValueUSD = usd
                        }
                        if let foilString = prices.usdFoil, let foil = Double(foilString) {
                            item.currentValueFoilUSD = foil
                        }
                    }
                }
                if !collectionItems.isEmpty { try context.save() }

                // Compute total collection value
                let totalValue = collectionItems.reduce(0.0) { sum, item in
                    let nonFoilCount = item.quantity - item.foilQuantity
                    let nonFoilValue = (item.currentValueUSD ?? 0) * Double(max(0, nonFoilCount))
                    let foilValue = (item.currentValueFoilUSD ?? item.currentValueUSD ?? 0) * Double(item.foilQuantity)
                    return sum + nonFoilValue + foilValue
                }

                return (updated, totalValue)
            }.value

            progress = 0.95
            UserDefaults.standard.set(collectionTotal, forKey: "collectionCachedValueUSD")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "collectionCachedValueAt")

            progress = 1.0

            // Clean up
            try? FileManager.default.removeItem(at: fileURL)

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastRefreshKey)
            print("[PriceRefresh] Updated \(updatedCount) card prices")

        } catch {
            print("[PriceRefresh] Failed: \(error.localizedDescription)")
        }
    }
}
