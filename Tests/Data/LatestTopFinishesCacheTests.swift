import Testing
import Foundation
@testable import MTGCardScanner

@Suite("LatestTopFinishesCache stale-fallback Tests")
struct LatestTopFinishesCacheTests {

    /// Test stub for `MTGTop8ServiceProtocol` whose `fetchLatestTop1`
    /// behavior the test controls. Other methods are unused by the
    /// cache and trap if invoked.
    final actor StubService: MTGTop8ServiceProtocol {
        enum Behavior: Sendable {
            case returns(MTGTop8Deck?)
            case throws_
        }

        var behavior: Behavior
        var callCount: Int = 0

        init(_ behavior: Behavior) {
            self.behavior = behavior
        }

        func setBehavior(_ behavior: Behavior) {
            self.behavior = behavior
        }

        func fetchLatestTop1(archetypeID: String, format: String) async throws -> MTGTop8Deck? {
            callCount += 1
            switch behavior {
            case .returns(let deck): return deck
            case .throws_: throw URLError(.notConnectedToInternet)
            }
        }

        // Unused — never called by this cache.
        func fetchCardData(name: String) async throws -> MTGTop8CardData { fatalError("unused") }
        func fetchCardData(name: String, format: String) async throws -> MTGTop8CardData { fatalError("unused") }
        func fetchTopDecks(archetype: String, format: String?, cardName: String?, maxPlacement: Int?) async throws -> [MTGTop8Deck] { fatalError("unused") }
        func fetchDecksByArchetypeID(_ archetypeID: String, format: String, maxPlacement: Int?) async throws -> [MTGTop8Deck] { fatalError("unused") }
        func fetchMostRecentDeck(archetypeID: String, format: String) async throws -> MTGTop8Deck? { fatalError("unused") }
        func fetchDecklist(deckID: String) async throws -> MTGTop8Decklist { fatalError("unused") }
    }

    private static func sampleDeck(id: String = "deck-1") -> MTGTop8Deck {
        MTGTop8Deck(
            deckID: id,
            name: "Burn",
            player: "Alice",
            event: "Modern Challenge",
            finish: "1",
            date: "01/05/26",
            format: "MO",
            level: 3
        )
    }

    private static func makeCache(
        service: StubService,
        monitor: MTGTop8AvailabilityMonitor,
        ttl: TimeInterval = 7 * 24 * 60 * 60
    ) -> LatestTopFinishesCache {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LatestTopFinishesCacheTests-\(UUID())", isDirectory: true)
        return LatestTopFinishesCache(
            service: service,
            availabilityMonitor: monitor,
            cacheDirectory: dir,
            ttl: ttl
        )
    }

    // MARK: - Monitor-gated fallback

    @Test("Serves stale entry when monitor reports MTGTop8 unavailable")
    func staleEntryServedWhenMonitorDown() async {
        let deck = Self.sampleDeck()
        let service = StubService(.returns(deck))
        let monitor = MTGTop8AvailabilityMonitor(
            failureThreshold: 1,
            unavailableDuration: 60 * 60
        )
        // Use a tiny TTL so the second call sees the entry as stale.
        let cache = Self.makeCache(service: service, monitor: monitor, ttl: 0.001)

        // Warm cache with a real fetch.
        let initial = await cache.latestTop1(archetypeID: "42", format: "MO")
        #expect(initial?.deckID == "deck-1")

        try? await Task.sleep(nanoseconds: 10_000_000)  // expire TTL

        // Monitor goes down; service is set to throw if asked.
        await monitor.recordFailure()
        #expect(await monitor.isAvailable == false)
        await service.setBehavior(.throws_)

        let stale = await cache.latestTop1(archetypeID: "42", format: "MO")

        #expect(stale?.deckID == "deck-1")  // served from cache
        #expect(await service.callCount == 1)  // service NOT called second time
    }

    @Test("Returns nil when monitor down and no cached entry exists")
    func nilWhenMonitorDownWithNoCache() async {
        let service = StubService(.returns(Self.sampleDeck()))
        let monitor = MTGTop8AvailabilityMonitor(
            failureThreshold: 1,
            unavailableDuration: 60 * 60
        )
        let cache = Self.makeCache(service: service, monitor: monitor)

        await monitor.recordFailure()
        #expect(await monitor.isAvailable == false)

        let result = await cache.latestTop1(archetypeID: "999", format: "MO")

        #expect(result == nil)
        #expect(await service.callCount == 0)  // never even attempted
    }

    // MARK: - Transient error fallback

    @Test("Falls back to stale entry when fetch throws (monitor still up)")
    func transientErrorFallsBackToStale() async {
        let deck = Self.sampleDeck()
        let service = StubService(.returns(deck))
        let monitor = MTGTop8AvailabilityMonitor()
        let cache = Self.makeCache(service: service, monitor: monitor, ttl: 0.001)

        // Warm cache.
        _ = await cache.latestTop1(archetypeID: "42", format: "MO")
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Now flip service to throw, but leave monitor "available" — this
        // models the FIRST failure of an outage, before the threshold.
        await service.setBehavior(.throws_)

        let result = await cache.latestTop1(archetypeID: "42", format: "MO")

        #expect(result?.deckID == "deck-1")  // served stale instead of nil
    }

    @Test("Successful fetch overwrites previously cached value")
    func successfulFetchOverwritesCache() async {
        let oldDeck = Self.sampleDeck(id: "old")
        let service = StubService(.returns(oldDeck))
        let monitor = MTGTop8AvailabilityMonitor()
        let cache = Self.makeCache(service: service, monitor: monitor, ttl: 0.001)

        _ = await cache.latestTop1(archetypeID: "42", format: "MO")
        try? await Task.sleep(nanoseconds: 10_000_000)

        let newDeck = Self.sampleDeck(id: "new")
        await service.setBehavior(.returns(newDeck))

        let result = await cache.latestTop1(archetypeID: "42", format: "MO")

        #expect(result?.deckID == "new")
    }
}
