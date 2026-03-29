import Testing
import Foundation
@testable import MTGCardScanner

// MARK: - Card Kingdom JSON Fixtures

private enum CardKingdomFixtures {

    static let priceListJSON = """
    {
        "meta": {
            "date": "2026-03-29",
            "version": "1.0"
        },
        "data": [
            {
                "id": 1001,
                "name": "Lightning Bolt",
                "edition": "Double Masters",
                "sku": "CK-2XM-117",
                "price_retail": 0.79,
                "price_buy": 0.35,
                "qty_retail": 20,
                "qty_buy": 100,
                "condition": "NM",
                "is_foil": false,
                "url": "https://www.cardkingdom.com/mtg/double-masters/lightning-bolt"
            },
            {
                "id": 1002,
                "name": "Lightning Bolt",
                "edition": "Double Masters",
                "sku": "CK-2XM-117-F",
                "price_retail": 2.49,
                "price_buy": 1.10,
                "qty_retail": 5,
                "qty_buy": 50,
                "condition": "NM",
                "is_foil": true,
                "url": "https://www.cardkingdom.com/mtg/double-masters/lightning-bolt-foil"
            },
            {
                "id": 2001,
                "name": "Sol Ring",
                "edition": "Commander Masters",
                "sku": "CK-CMM-123",
                "price_retail": 1.49,
                "price_buy": 0.80,
                "qty_retail": 50,
                "qty_buy": 200,
                "condition": "NM",
                "is_foil": false,
                "url": "https://www.cardkingdom.com/mtg/commander-masters/sol-ring"
            }
        ]
    }
    """.data(using: .utf8)!

    static let emptyListJSON = """
    {
        "meta": {
            "date": "2026-03-29",
            "version": "1.0"
        },
        "data": []
    }
    """.data(using: .utf8)!

    static let malformedJSON = "{ not valid json }".data(using: .utf8)!
}

// MARK: - CardKingdomPriceService Tests

@Suite("CardKingdomPriceService Tests")
struct CardKingdomPriceServiceTests {

    // MARK: - Find Card by Name and Set

    @Test("Finds card by name and set, returns NM retail and buylist prices")
    func findsCardByNameAndSet() async throws {
        let httpClient = MockHTTPClient.success(
            data: CardKingdomFixtures.priceListJSON,
            url: URL(string: "https://api.cardkingdom.com/api/pricelist")
        )
        let service = CardKingdomPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt", setName: "Double Masters")

        #expect(price != nil)
        #expect(price?.retailUSD == 0.79)
        #expect(price?.buylistUSD == 0.35)
    }

    // MARK: - Price Formatting

    @Test("Formats retail price as dollar string")
    func formatsRetailPrice() async throws {
        let httpClient = MockHTTPClient.success(
            data: CardKingdomFixtures.priceListJSON,
            url: URL(string: "https://api.cardkingdom.com/api/pricelist")
        )
        let service = CardKingdomPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt", setName: "Double Masters")

        #expect(price?.formattedRetail == "$0.79")
    }

    @Test("Formats buylist price as dollar string")
    func formatsBuylistPrice() async throws {
        let httpClient = MockHTTPClient.success(
            data: CardKingdomFixtures.priceListJSON,
            url: URL(string: "https://api.cardkingdom.com/api/pricelist")
        )
        let service = CardKingdomPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt", setName: "Double Masters")

        #expect(price?.formattedBuylist == "$0.35")
    }

    // MARK: - Card Not Found

    @Test("Returns nil for card not in list")
    func returnsNilForCardNotInList() async throws {
        let httpClient = MockHTTPClient.success(
            data: CardKingdomFixtures.priceListJSON,
            url: URL(string: "https://api.cardkingdom.com/api/pricelist")
        )
        let service = CardKingdomPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Black Lotus", setName: "Alpha")

        #expect(price == nil)
    }

    @Test("Returns nil when price list is empty")
    func returnsNilWhenEmptyList() async throws {
        let httpClient = MockHTTPClient.success(
            data: CardKingdomFixtures.emptyListJSON,
            url: URL(string: "https://api.cardkingdom.com/api/pricelist")
        )
        let service = CardKingdomPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt", setName: "Double Masters")

        #expect(price == nil)
    }

    // MARK: - Filters Out Foil

    @Test("Returns non-foil NM price, not foil")
    func filtersOutFoil() async throws {
        let httpClient = MockHTTPClient.success(
            data: CardKingdomFixtures.priceListJSON,
            url: URL(string: "https://api.cardkingdom.com/api/pricelist")
        )
        let service = CardKingdomPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt", setName: "Double Masters")

        // Should match the non-foil entry (0.79), not the foil entry (2.49)
        #expect(price?.retailUSD == 0.79)
    }

    // MARK: - Case-Insensitive Matching

    @Test("Card name matching is case-insensitive")
    func caseInsensitiveMatching() async throws {
        let httpClient = MockHTTPClient.success(
            data: CardKingdomFixtures.priceListJSON,
            url: URL(string: "https://api.cardkingdom.com/api/pricelist")
        )
        let service = CardKingdomPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "lightning bolt", setName: "double masters")

        #expect(price != nil)
        #expect(price?.retailUSD == 0.79)
    }

    // MARK: - Network Error

    @Test("Network failure throws CardKingdomError.networkError")
    func handlesNetworkError() async {
        let httpClient = MockHTTPClient.failure(URLError(.notConnectedToInternet))
        let service = CardKingdomPriceService(httpClient: httpClient)

        do {
            _ = try await service.fetchNMPrice(cardName: "Lightning Bolt", setName: "Double Masters")
            Issue.record("Expected CardKingdomError.networkError")
        } catch let error as CardKingdomError {
            if case .networkError = error {
                // Expected
            } else {
                Issue.record("Expected CardKingdomError.networkError but got \(error)")
            }
        } catch {
            Issue.record("Expected CardKingdomError but got \(error)")
        }
    }

    @Test("Malformed JSON throws CardKingdomError.decodingError")
    func handlesDecodingError() async {
        let httpClient = MockHTTPClient.success(
            data: CardKingdomFixtures.malformedJSON,
            url: URL(string: "https://api.cardkingdom.com/api/pricelist")
        )
        let service = CardKingdomPriceService(httpClient: httpClient)

        do {
            _ = try await service.fetchNMPrice(cardName: "Lightning Bolt", setName: "Double Masters")
            Issue.record("Expected CardKingdomError.decodingError")
        } catch let error as CardKingdomError {
            if case .decodingError = error {
                // Expected
            } else {
                Issue.record("Expected CardKingdomError.decodingError but got \(error)")
            }
        } catch {
            Issue.record("Expected CardKingdomError but got \(error)")
        }
    }

    @Test("Server error throws CardKingdomError.serverError")
    func handlesServerError() async {
        let httpClient = MockHTTPClient.success(
            data: Data(),
            statusCode: 500,
            url: URL(string: "https://api.cardkingdom.com/api/pricelist")
        )
        let service = CardKingdomPriceService(httpClient: httpClient)

        do {
            _ = try await service.fetchNMPrice(cardName: "Lightning Bolt", setName: "Double Masters")
            Issue.record("Expected CardKingdomError.serverError")
        } catch let error as CardKingdomError {
            if case .serverError = error {
                // Expected
            } else {
                Issue.record("Expected CardKingdomError.serverError but got \(error)")
            }
        } catch {
            Issue.record("Expected CardKingdomError but got \(error)")
        }
    }
}
