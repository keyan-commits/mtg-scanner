import Testing
import Foundation
@testable import MTGCardScanner

// MARK: - Mock EDHREC JSON Fixtures

private enum EDHRECFixtures {

    static let solRingResponseJSON = """
    {
        "container": {
            "json_dict": {
                "card": {
                    "name": "Sol Ring",
                    "num_decks": 456789,
                    "potential_decks": 512000,
                    "url": "/pages/cards/sol-ring"
                },
                "cardlists": [
                    {
                        "tag": "topcommanders",
                        "cardviews": [
                            {
                                "name": "Atraxa, Praetors' Voice",
                                "inclusion": 9800,
                                "potential_decks": 10000,
                                "label": "98% of decks",
                                "image": "https://cards.scryfall.io/normal/atraxa.jpg"
                            },
                            {
                                "name": "Korvold, Fae-Cursed King",
                                "inclusion": 8500,
                                "potential_decks": 9000,
                                "label": "94% of decks",
                                "image": "https://cards.scryfall.io/normal/korvold.jpg"
                            },
                            {
                                "name": "Muldrotha, the Gravetide",
                                "inclusion": 7200,
                                "potential_decks": 8000,
                                "label": "90% of decks",
                                "image": "https://cards.scryfall.io/normal/muldrotha.jpg"
                            }
                        ]
                    },
                    {
                        "tag": "topdecks",
                        "cardviews": [
                            {
                                "name": "Unrelated Entry",
                                "inclusion": 100,
                                "potential_decks": 200,
                                "label": "50% of decks"
                            }
                        ]
                    }
                ]
            }
        }
    }
    """.data(using: .utf8)!

    static let notFoundHTML = """
    <html><body>404 Not Found</body></html>
    """.data(using: .utf8)!
}

// MARK: - EDHRECService Tests

@Suite("EDHRECService Tests")
struct EDHRECServiceTests {

    // MARK: - Successful Fetch

    @Test("fetchCardData parses card-level stats correctly")
    func fetchCardDataParsesCardStats() async throws {
        let httpClient = MockHTTPClient.success(
            data: EDHRECFixtures.solRingResponseJSON,
            url: URL(string: "https://json.edhrec.com/pages/cards/sol-ring.json")
        )
        let service = EDHRECService(httpClient: httpClient)

        let cardData = try await service.fetchCardData(name: "Sol Ring")

        #expect(cardData.cardName == "Sol Ring")
        #expect(cardData.numDecks == 456789)
        #expect(cardData.potentialDecks == 512000)

        let expectedPercent = Double(456789) / Double(512000) * 100
        #expect(abs(cardData.inclusionPercent - expectedPercent) < 0.01)
    }

    @Test("fetchCardData parses top commanders with names and inclusion percentages")
    func fetchCardDataParsesTopCommanders() async throws {
        let httpClient = MockHTTPClient.success(
            data: EDHRECFixtures.solRingResponseJSON,
            url: URL(string: "https://json.edhrec.com/pages/cards/sol-ring.json")
        )
        let service = EDHRECService(httpClient: httpClient)

        let cardData = try await service.fetchCardData(name: "Sol Ring")

        #expect(cardData.topCommanders.count == 3)

        let first = cardData.topCommanders[0]
        #expect(first.name == "Atraxa, Praetors' Voice")
        #expect(first.numDecks == 9800)
        #expect(first.potentialDecks == 10000)
        #expect(first.inclusionPercent == 98.0)
        #expect(first.imageURI == "https://cards.scryfall.io/normal/atraxa.jpg")

        let second = cardData.topCommanders[1]
        #expect(second.name == "Korvold, Fae-Cursed King")
        #expect(second.numDecks == 8500)
        #expect(second.potentialDecks == 9000)
        #expect(abs(second.inclusionPercent - (8500.0 / 9000.0 * 100)) < 0.01)
        #expect(second.imageURI == "https://cards.scryfall.io/normal/korvold.jpg")

        let third = cardData.topCommanders[2]
        #expect(third.name == "Muldrotha, the Gravetide")
    }

    // MARK: - Error Handling

    @Test("404 response throws cardNotFound")
    func handlesCardNotFound() async {
        let httpClient = MockHTTPClient.success(
            data: EDHRECFixtures.notFoundHTML,
            statusCode: 404,
            url: URL(string: "https://json.edhrec.com/pages/cards/nonexistent-card.json")
        )
        let service = EDHRECService(httpClient: httpClient)

        do {
            _ = try await service.fetchCardData(name: "Nonexistent Card")
            Issue.record("Expected EDHRECError.cardNotFound")
        } catch let error as EDHRECError {
            #expect(error == .cardNotFound)
        } catch {
            Issue.record("Expected EDHRECError.cardNotFound but got \(error)")
        }
    }

    @Test("Network failure throws networkError")
    func handlesNetworkError() async {
        let urlError = URLError(.notConnectedToInternet)
        let httpClient = MockHTTPClient.failure(urlError)
        let service = EDHRECService(httpClient: httpClient)

        do {
            _ = try await service.fetchCardData(name: "Sol Ring")
            Issue.record("Expected EDHRECError.networkError")
        } catch let error as EDHRECError {
            if case .networkError = error {
                // Expected
            } else {
                Issue.record("Expected EDHRECError.networkError but got \(error)")
            }
        } catch {
            Issue.record("Expected EDHRECError.networkError but got \(error)")
        }
    }

    @Test("Malformed JSON throws decodingError")
    func handlesDecodingError() async {
        let malformed = "{ not valid json }".data(using: .utf8)!
        let httpClient = MockHTTPClient.success(
            data: malformed,
            url: URL(string: "https://json.edhrec.com/pages/cards/sol-ring.json")
        )
        let service = EDHRECService(httpClient: httpClient)

        do {
            _ = try await service.fetchCardData(name: "Sol Ring")
            Issue.record("Expected EDHRECError.decodingError")
        } catch let error as EDHRECError {
            if case .decodingError = error {
                // Expected
            } else {
                Issue.record("Expected EDHRECError.decodingError but got \(error)")
            }
        } catch {
            Issue.record("Expected EDHRECError.decodingError but got \(error)")
        }
    }

    // MARK: - Name Sanitization

    @Test("Sanitizes apostrophes: Sensei's Divining Top → senseis-divining-top")
    func sanitizesApostrophes() async throws {
        let capturingClient = CapturingHTTPClient(
            responseData: EDHRECFixtures.solRingResponseJSON,
            statusCode: 200
        )
        let service = EDHRECService(httpClient: capturingClient)

        _ = try? await service.fetchCardData(name: "Sensei's Divining Top")

        let requestedURL = capturingClient.lastRequest?.url?.absoluteString ?? ""
        #expect(requestedURL.contains("senseis-divining-top"))
    }

    @Test("Sanitizes commas: Thalia, Guardian of Thraben → thalia-guardian-of-thraben")
    func sanitizesCommas() async throws {
        let capturingClient = CapturingHTTPClient(
            responseData: EDHRECFixtures.solRingResponseJSON,
            statusCode: 200
        )
        let service = EDHRECService(httpClient: capturingClient)

        _ = try? await service.fetchCardData(name: "Thalia, Guardian of Thraben")

        let requestedURL = capturingClient.lastRequest?.url?.absoluteString ?? ""
        #expect(requestedURL.contains("thalia-guardian-of-thraben"))
    }

    // MARK: - Top Commanders Limit

    @Test("Top commanders are limited to 10")
    func limitsTopCommandersToTen() async throws {
        // Build a JSON response with 15 commanders
        var commanderEntries: [String] = []
        for i in 1...15 {
            let name = "Commander \(i)"
            let inclusion = 1000 - i * 10
            let label = "\(100 - i)% of decks"
            commanderEntries.append("""
            {
                "name": "\(name)",
                "inclusion": \(inclusion),
                "potential_decks": 1000,
                "label": "\(label)"
            }
            """)
        }
        let manyCommandersJSON = """
        {
            "container": {
                "json_dict": {
                    "card": {
                        "name": "Test Card",
                        "num_decks": 100,
                        "potential_decks": 200
                    },
                    "cardlists": [
                        {
                            "tag": "topcommanders",
                            "cardviews": [\(commanderEntries.joined(separator: ","))]
                        }
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let httpClient = MockHTTPClient.success(data: manyCommandersJSON)
        let service = EDHRECService(httpClient: httpClient)

        let cardData = try await service.fetchCardData(name: "Test Card")

        #expect(cardData.topCommanders.count == 10)
    }
}
