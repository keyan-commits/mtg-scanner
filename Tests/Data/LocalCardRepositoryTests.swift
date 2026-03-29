import Testing
import Foundation
import SwiftData
@testable import MTGCardScanner

@Suite("LocalCardRepository Tests")
@MainActor
struct LocalCardRepositoryTests {

    // MARK: - Helpers

    private func makePopulatedDatabaseManager() async throws -> DatabaseManager {
        let manager = try DatabaseManager(inMemory: true)

        let legalities = ["standard": "not_legal", "modern": "legal"]
        let imageURIs = ["normal": "https://cards.scryfall.io/normal/front/e/2/e2d1f9ad.jpg"]
        let legalitiesJSON = String(data: try JSONSerialization.data(withJSONObject: legalities), encoding: .utf8)!
        let imageURIsJSON = String(data: try JSONSerialization.data(withJSONObject: imageURIs), encoding: .utf8)!

        let record1 = CardRecord(
            scryfallID: "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43",
            name: "Lightning Bolt",
            manaCost: "{R}",
            typeLine: "Instant",
            oracleText: "Lightning Bolt deals 3 damage to any target.",
            setCode: "2xm",
            setName: "Double Masters",
            setType: "masters",
            collectorNumber: "117",
            rarity: "uncommon",
            artist: "Test Artist",
            priceUSD: "1.50",
            priceUSDFoil: "3.25",
            priceEUR: "1.10",
            priceEURFoil: "2.80",
            priceTix: "0.40",
            legalitiesJSON: legalitiesJSON,
            imageURIsJSON: imageURIsJSON,
            printsSearchURI: "https://api.scryfall.com/cards/search?order=released&q=oracleid%3Abc9b08eb"
        )

        let record2 = CardRecord(
            scryfallID: "aaaa-bbbb-cccc-dddd",
            name: "Lightning Helix",
            manaCost: "{R}{W}",
            typeLine: "Instant",
            oracleText: "Lightning Helix deals 3 damage to any target and you gain 3 life.",
            setCode: "rav",
            setName: "Ravnica",
            setType: "expansion",
            collectorNumber: "68",
            rarity: "uncommon",
            artist: "Test Artist",
            priceUSD: "0.50",
            priceUSDFoil: nil,
            priceEUR: nil,
            priceEURFoil: nil,
            priceTix: nil,
            legalitiesJSON: legalitiesJSON,
            imageURIsJSON: "{}",
            printsSearchURI: nil
        )

        let record3 = CardRecord(
            scryfallID: "1111-2222-3333-4444",
            name: "Counterspell",
            manaCost: "{U}{U}",
            typeLine: "Instant",
            oracleText: "Counter target spell.",
            setCode: "ice",
            setName: "Ice Age",
            setType: "expansion",
            collectorNumber: "64",
            rarity: "common",
            artist: nil,
            priceUSD: "1.00",
            priceUSDFoil: nil,
            priceEUR: nil,
            priceEURFoil: nil,
            priceTix: nil,
            legalitiesJSON: legalitiesJSON,
            imageURIsJSON: "{}",
            printsSearchURI: nil
        )

        let context = ModelContext(manager.modelContainer)
        context.insert(record1)
        context.insert(record2)
        context.insert(record3)
        try context.save()

        return manager
    }

    // MARK: - identifyCard Tests

    @Test("identifyCard returns correct domain Card for existing card")
    func identifyCardReturnsCorrectCard() async throws {
        let manager = try await makePopulatedDatabaseManager()
        let repository = LocalCardRepository(databaseManager: manager)

        let card = try await repository.identifyCard(name: "Lightning Bolt")

        #expect(card.name == "Lightning Bolt")
        #expect(card.scryfallID == "e2d1f9ad-c9b3-4c08-8352-ebfcd85ded43")
        #expect(card.manaCost == "{R}")
        #expect(card.typeLine == "Instant")
        #expect(card.rarity == .uncommon)
        #expect(card.set.code == "2xm")
        #expect(card.prices.usd == "1.50")
    }

    @Test("identifyCard throws cardNotFound for missing card")
    func identifyCardThrowsForMissingCard() async throws {
        let manager = try await makePopulatedDatabaseManager()
        let repository = LocalCardRepository(databaseManager: manager)

        await #expect(throws: CardRepositoryError.cardNotFound) {
            _ = try await repository.identifyCard(name: "Nonexistent Card")
        }
    }

    @Test("identifyCard is case-insensitive")
    func identifyCardIsCaseInsensitive() async throws {
        let manager = try await makePopulatedDatabaseManager()
        let repository = LocalCardRepository(databaseManager: manager)

        let card = try await repository.identifyCard(name: "lightning bolt")

        #expect(card.name == "Lightning Bolt")
    }

    // MARK: - searchCards Tests

    @Test("searchCards returns matching cards")
    func searchCardsReturnsMatches() async throws {
        let manager = try await makePopulatedDatabaseManager()
        let repository = LocalCardRepository(databaseManager: manager)

        let cards = try await repository.searchCards(query: "Lightning")

        #expect(cards.count == 2)
        let names = cards.map(\.name).sorted()
        #expect(names == ["Lightning Bolt", "Lightning Helix"])
    }

    @Test("searchCards returns empty array for no matches")
    func searchCardsReturnsEmptyForNoMatches() async throws {
        let manager = try await makePopulatedDatabaseManager()
        let repository = LocalCardRepository(databaseManager: manager)

        let cards = try await repository.searchCards(query: "Nonexistent")

        #expect(cards.isEmpty)
    }

    @Test("searchCards is case-insensitive")
    func searchCardsIsCaseInsensitive() async throws {
        let manager = try await makePopulatedDatabaseManager()
        let repository = LocalCardRepository(databaseManager: manager)

        let cards = try await repository.searchCards(query: "lightning")

        #expect(cards.count == 2)
    }

    // MARK: - fetchCard Tests

    @Test("fetchCard by set and collector number returns correct card")
    func fetchCardBySetReturnsCorrectCard() async throws {
        let manager = try await makePopulatedDatabaseManager()
        let repository = LocalCardRepository(databaseManager: manager)

        let card = try await repository.fetchCard(set: "2xm", collectorNumber: "117")

        #expect(card.name == "Lightning Bolt")
        #expect(card.set.code == "2xm")
        #expect(card.collectorNumber == "117")
    }

    @Test("fetchCard throws cardNotFound for missing set/number combination")
    func fetchCardThrowsForMissingCard() async throws {
        let manager = try await makePopulatedDatabaseManager()
        let repository = LocalCardRepository(databaseManager: manager)

        await #expect(throws: CardRepositoryError.cardNotFound) {
            _ = try await repository.fetchCard(set: "xxx", collectorNumber: "999")
        }
    }
}
