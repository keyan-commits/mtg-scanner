import Foundation

/// Persists the MTGStocks interests payload across app launches so the home
/// screen's "Price Movers" section can show stale data immediately and only
/// refresh in the background when needed. Without this layer the in-memory
/// cache on `MTGStocksService` is wiped on every launch, forcing a network
/// round-trip before the section renders.
struct MTGStocksInterestsDiskCache: Sendable {

    struct Blob: Codable, Equatable, Sendable {
        let entries: [MTGStocksInterest]
        let fetchedAt: Date
    }

    let url: URL?

    /// Default location: `Application Support/MTGCardScanner/mtgstocks_interests_cache.json`.
    static func defaultURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("MTGCardScanner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mtgstocks_interests_cache.json")
    }

    init(url: URL? = MTGStocksInterestsDiskCache.defaultURL()) {
        self.url = url
    }

    /// Returns the blob if present and decodable. A corrupt file is removed so
    /// the next save lands cleanly — we'd rather lose one cache than crash on
    /// every launch decoding a bad payload.
    func load() -> Blob? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let blob = try? JSONDecoder().decode(Blob.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return blob
    }

    func save(_ blob: Blob) {
        guard let url else { return }
        guard let data = try? JSONEncoder().encode(blob) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
