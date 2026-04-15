import Testing
import Foundation
@testable import MTGCardScanner

@Suite("ArchetypeSearchService Tests")
struct ArchetypeSearchServiceTests {

    // MARK: - Fixtures

    private static func makeArchetype(
        id: String,
        name: String,
        format: String = "Modern",
        mainboard: [String: Int]
    ) -> ClassicArchetype {
        ClassicArchetype(
            id: id,
            name: name,
            era: "2020",
            format: format,
            mainboard: mainboard,
            sideboard: nil,
            source: "test",
            description: "test"
        )
    }

    private static let affinityRobots = makeArchetype(
        id: "affinity-robots",
        name: "Affinity (Robots)",
        mainboard: [
            "Cranial Plating": 4,
            "Arcbound Ravager": 4,
            "Steel Overseer": 3,
            "Mountain": 4,
        ]
    )

    private static let affinityStandard = makeArchetype(
        id: "affinity-standard",
        name: "Affinity (Standard)",
        mainboard: [
            "Disciple of the Vault": 4,
            "Arcbound Worker": 4,
            "Forest": 4,
        ]
    )

    private static let goblins = makeArchetype(
        id: "goblins",
        name: "Goblins",
        mainboard: [
            "Goblin Lackey": 4,
            "Goblin Piledriver": 4,
            "Mountain": 20,
        ]
    )

    private static let unrelated = makeArchetype(
        id: "the-rock",
        name: "The Rock",
        mainboard: [
            "Tarmogoyf": 4,
            "Thoughtseize": 4,
        ]
    )

    private static let allFixtures: [ClassicArchetype] = [
        affinityRobots, affinityStandard, goblins, unrelated,
    ]

    // MARK: - Mock online index

    private struct StubArchetypeIndex: MTGTop8ArchetypeIndexProtocol {
        let entries: [IndexedArchetype]

        func archetypes(forceRefresh: Bool) async throws -> [IndexedArchetype] {
            entries
        }

        func search(_ query: String, in formats: [MTGTop8Format], limit: Int) async throws -> [IndexedArchetype] {
            let lowered = query.lowercased()
            return entries.filter {
                formats.contains($0.format) && $0.name.lowercased().contains(lowered)
            }
        }
    }

    private static func makeService(
        classic: [ClassicArchetype] = allFixtures,
        online: [IndexedArchetype] = []
    ) -> ArchetypeSearchService {
        ArchetypeSearchService(
            classicArchetypes: classic,
            onlineIndex: StubArchetypeIndex(entries: online),
            onlineFormats: [.modern, .standard, .legacy]
        )
    }

    // MARK: - Classic-only search

    @Test("Empty query returns no results")
    func emptyQueryReturnsNothing() async {
        let service = Self.makeService()
        #expect(await service.search("").isEmpty)
        #expect(await service.search("   ").isEmpty)
    }

    @Test("Query shorter than 2 characters returns no results")
    func shortQueryReturnsNothing() async {
        let service = Self.makeService()
        #expect(await service.search("a").isEmpty)
    }

    @Test("Search is case-insensitive across both sources")
    func caseInsensitive() async {
        let service = Self.makeService()
        let upper = await service.search("AFFINITY")
        let lower = await service.search("affinity")
        let mixed = await service.search("Affinity")
        #expect(upper.count == 2)
        #expect(lower.count == 2)
        #expect(mixed.count == 2)
    }

    @Test("Substring matching finds both Affinity variants")
    func substringMatching() async {
        let service = Self.makeService()
        let results = await service.search("Affinity")
        #expect(results.count == 2)
        let names = Set(results.map(\.name))
        #expect(names.contains("Affinity (Robots)"))
        #expect(names.contains("Affinity (Standard)"))
    }

    @Test("Classic results carry .classic source with a usable signature card")
    func classicResultHasSignature() async {
        let service = Self.makeService()
        let results = await service.search("Goblins")
        #expect(results.count == 1)
        guard case let .classic(signature) = results[0].source else {
            Issue.record("Expected .classic source")
            return
        }
        #expect(signature != "Mountain")
        #expect(signature.hasPrefix("Goblin"))
    }

    @Test("Non-matching query returns empty")
    func noMatch() async {
        let service = Self.makeService()
        #expect(await service.search("xyzzy").isEmpty)
    }

    // MARK: - Online source

    @Test("Online archetypes appear in results")
    func onlineResultsIncluded() async {
        let online = [
            IndexedArchetype(archetypeID: "42", name: "Boros Energy", format: .modern)
        ]
        let service = Self.makeService(online: online)

        let results = await service.search("Boros")
        #expect(results.count == 1)
        #expect(results[0].name == "Boros Energy")
        #expect(results[0].format == "Modern")
        guard case let .online(id, code) = results[0].source else {
            Issue.record("Expected .online source")
            return
        }
        #expect(id == "42")
        #expect(code == "MO")
    }

    @Test("Online wins over classic when names collide")
    func onlinePriorityOnNameCollision() async {
        let online = [
            IndexedArchetype(archetypeID: "99", name: "Goblins", format: .legacy)
        ]
        let service = Self.makeService(online: online)

        let results = await service.search("Goblins")
        #expect(results.count == 1)  // Classic Goblins is hidden
        guard case .online = results[0].source else {
            Issue.record("Expected online source to win the collision")
            return
        }
    }

    @Test("Classic results still appear when online has different name")
    func bothSourcesContribute() async {
        let online = [
            IndexedArchetype(archetypeID: "1", name: "Burn", format: .modern)
        ]
        let service = Self.makeService(online: online)

        let results = await service.search("Goblins")
        // Online "Burn" doesn't match the query; classic "Goblins" does.
        #expect(results.count == 1)
        #expect(results[0].name == "Goblins")
    }

    // MARK: - Signature card helper

    @Test("Signature card picks the highest-count non-basic mainboard entry")
    func signatureCardPicksHighestCount() {
        let result = ArchetypeSearchService.signatureCard(for: Self.affinityRobots)
        // Cranial Plating (4) and Arcbound Ravager (4) tie; alphabetically
        // later wins → Cranial Plating
        #expect(result == "Cranial Plating")
    }

    @Test("Signature card skips basic lands")
    func signatureCardSkipsBasics() {
        let result = ArchetypeSearchService.signatureCard(for: Self.goblins)
        #expect(result != "Mountain")
        #expect(result == "Goblin Piledriver" || result == "Goblin Lackey")
    }
}
