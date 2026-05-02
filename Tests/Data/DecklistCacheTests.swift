import Testing
import Foundation
@testable import MTGCardScanner

@Suite("DecklistCache stale-fallback Tests")
struct DecklistCacheTests {

    final actor StubService: MTGTop8ServiceProtocol {
        enum Behavior: Sendable {
            case returns(MTGTop8Decklist)
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

        func fetchDecklist(deckID: String) async throws -> MTGTop8Decklist {
            callCount += 1
            switch behavior {
            case .returns(let list): return list
            case .throws_: throw URLError(.notConnectedToInternet)
            }
        }

        func fetchCardData(name: String) async throws -> MTGTop8CardData { fatalError("unused") }
        func fetchCardData(name: String, format: String) async throws -> MTGTop8CardData { fatalError("unused") }
        func fetchTopDecks(archetype: String, format: String?, cardName: String?, maxPlacement: Int?) async throws -> [MTGTop8Deck] { fatalError("unused") }
        func fetchDecksByArchetypeID(_ archetypeID: String, format: String, maxPlacement: Int?) async throws -> [MTGTop8Deck] { fatalError("unused") }
        func fetchLatestTop1(archetypeID: String, format: String) async throws -> MTGTop8Deck? { fatalError("unused") }
        func fetchMostRecentDeck(archetypeID: String, format: String) async throws -> MTGTop8Deck? { fatalError("unused") }
    }

    private static func sampleDecklist(name: String = "Lightning Bolt") -> MTGTop8Decklist {
        MTGTop8Decklist(
            mainboard: [MTGTop8DecklistEntry(quantity: 4, cardName: name)],
            sideboard: []
        )
    }

    private static func makeCache(
        service: StubService,
        monitor: MTGTop8AvailabilityMonitor,
        ttl: TimeInterval = 14 * 24 * 60 * 60
    ) -> DecklistCache {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DecklistCacheTests-\(UUID())", isDirectory: true)
        return DecklistCache(
            service: service,
            availabilityMonitor: monitor,
            cacheDirectory: dir,
            ttl: ttl
        )
    }

    @Test("Serves stale decklist when monitor reports MTGTop8 unavailable")
    func staleDecklistServedWhenMonitorDown() async {
        let original = Self.sampleDecklist(name: "Lightning Bolt")
        let service = StubService(.returns(original))
        let monitor = MTGTop8AvailabilityMonitor(
            failureThreshold: 1,
            unavailableDuration: 60 * 60
        )
        let cache = Self.makeCache(service: service, monitor: monitor, ttl: 0.001)

        let initial = await cache.decklist(deckID: "deck-1")
        #expect(initial?.mainboard.first?.cardName == "Lightning Bolt")

        try? await Task.sleep(nanoseconds: 10_000_000)
        await monitor.recordFailure()
        await service.setBehavior(.throws_)

        let stale = await cache.decklist(deckID: "deck-1")

        #expect(stale?.mainboard.first?.cardName == "Lightning Bolt")
        #expect(await service.callCount == 1)  // skipped network on second call
    }

    @Test("Returns nil when monitor down and decklist never cached")
    func nilWhenMonitorDownAndUncached() async {
        let service = StubService(.returns(Self.sampleDecklist()))
        let monitor = MTGTop8AvailabilityMonitor(
            failureThreshold: 1,
            unavailableDuration: 60 * 60
        )
        let cache = Self.makeCache(service: service, monitor: monitor)

        await monitor.recordFailure()

        let result = await cache.decklist(deckID: "never-fetched")

        #expect(result == nil)
        #expect(await service.callCount == 0)
    }

    @Test("Transient error falls back to stale instead of returning nil")
    func transientErrorFallsBackToStale() async {
        let original = Self.sampleDecklist(name: "Lightning Bolt")
        let service = StubService(.returns(original))
        let monitor = MTGTop8AvailabilityMonitor()
        let cache = Self.makeCache(service: service, monitor: monitor, ttl: 0.001)

        _ = await cache.decklist(deckID: "deck-1")
        try? await Task.sleep(nanoseconds: 10_000_000)

        await service.setBehavior(.throws_)

        let result = await cache.decklist(deckID: "deck-1")

        #expect(result?.mainboard.first?.cardName == "Lightning Bolt")
    }
}
