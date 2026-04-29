import Testing
import Foundation
@testable import MTGCardScanner

@Suite("MTGStocksInterestsDiskCache")
struct MTGStocksInterestsDiskCacheTests {

    /// Each test gets its own tmp file so writes don't bleed between tests.
    private func tempCache() -> (cache: MTGStocksInterestsDiskCache, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("interests_cache_\(UUID().uuidString).json")
        return (MTGStocksInterestsDiskCache(url: url), url)
    }

    private func sample() -> MTGStocksInterestsDiskCache.Blob {
        let entries = [
            MTGStocksInterest(id: 1, name: "Tarmogoyf", setName: "Future Sight",
                              setCode: "FUT", currentPrice: 35.0, previousPrice: 30.0,
                              percentageChange: 16.66),
            MTGStocksInterest(id: 2, name: "Force of Will", setName: "Alliances",
                              setCode: "ALL", currentPrice: 95.0, previousPrice: 80.0,
                              percentageChange: 18.75)
        ]
        return MTGStocksInterestsDiskCache.Blob(entries: entries, fetchedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Round-trip preserves entries and fetchedAt across instances")
    func roundTrip() {
        let (cache, url) = tempCache()
        defer { try? FileManager.default.removeItem(at: url) }

        let blob = sample()
        cache.save(blob)

        // Fresh instance pointed at the same URL — simulates an app restart.
        let reloaded = MTGStocksInterestsDiskCache(url: url).load()
        #expect(reloaded == blob)
    }

    @Test("Missing file returns nil without error")
    func missingFileReturnsNil() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope_\(UUID().uuidString).json")
        let cache = MTGStocksInterestsDiskCache(url: url)
        #expect(cache.load() == nil)
    }

    @Test("Corrupt file is removed and load returns nil")
    func corruptFileFallsBack() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt_\(UUID().uuidString).json")
        try Data("not valid json".utf8).write(to: url)

        let cache = MTGStocksInterestsDiskCache(url: url)
        #expect(cache.load() == nil)
        // The corrupt file should be cleaned up so the next save lands cleanly.
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test("Save with nil URL is a no-op (no crash)")
    func nilURLIsSafe() {
        let cache = MTGStocksInterestsDiskCache(url: nil)
        cache.save(sample())  // must not crash
        #expect(cache.load() == nil)
    }

    @Test("Default URL points into Application Support")
    func defaultURLLocation() {
        let url = MTGStocksInterestsDiskCache.defaultURL()
        #expect(url != nil)
        #expect(url?.lastPathComponent == "mtgstocks_interests_cache.json")
        #expect(url?.path.contains("MTGCardScanner") == true)
    }
}
