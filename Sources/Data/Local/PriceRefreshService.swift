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
            let context = ModelContext(databaseManager.modelContainer)

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

            // Fetch all existing records and update prices in batches
            let descriptor = FetchDescriptor<CardRecord>()
            let records = try context.fetch(descriptor)
            let total = records.count
            var updated = 0

            for record in records {
                if let prices = priceLookup[record.scryfallID] {
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
                    progress = 0.6 + 0.35 * Double(updated) / Double(total)
                }
            }

            try context.save()
            progress = 1.0

            // Clean up
            try? FileManager.default.removeItem(at: fileURL)

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastRefreshKey)
            print("[PriceRefresh] Updated \(updated) card prices")

        } catch {
            print("[PriceRefresh] Failed: \(error.localizedDescription)")
        }
    }
}
