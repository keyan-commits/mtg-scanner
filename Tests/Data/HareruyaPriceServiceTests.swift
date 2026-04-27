import Testing
import Foundation
@testable import MTGCardScanner

// MARK: - Hareruya JSON Fixtures

private enum HareruyaFixtures {

    static let nmNonFoilResultJSON = """
    {
        "response": {
            "numFound": 3,
            "docs": [
                {
                    "name": "Lightning Bolt",
                    "price": "110",
                    "card_condition": 1,
                    "foil_flg": 0,
                    "stock": 5
                },
                {
                    "name": "Lightning Bolt",
                    "price": "90",
                    "card_condition": 2,
                    "foil_flg": 0,
                    "stock": 3
                },
                {
                    "name": "Lightning Bolt",
                    "price": "330",
                    "card_condition": 1,
                    "foil_flg": 1,
                    "stock": 1
                }
            ]
        }
    }
    """.data(using: .utf8)!

    static let onlyFoilResultJSON = """
    {
        "response": {
            "numFound": 1,
            "docs": [
                {
                    "name": "Lightning Bolt",
                    "price": "330",
                    "card_condition": 1,
                    "foil_flg": 1,
                    "stock": 1
                }
            ]
        }
    }
    """.data(using: .utf8)!

    static let noDocsResultJSON = """
    {
        "response": {
            "numFound": 0,
            "docs": []
        }
    }
    """.data(using: .utf8)!

    static let onlySpConditionJSON = """
    {
        "response": {
            "numFound": 1,
            "docs": [
                {
                    "name": "Lightning Bolt",
                    "price": "80",
                    "card_condition": 2,
                    "foil_flg": 0,
                    "stock": 2
                }
            ]
        }
    }
    """.data(using: .utf8)!

    static let malformedJSON = "{ not valid json }".data(using: .utf8)!
}

// MARK: - HareruyaPriceService Tests

@Suite("HareruyaPriceService Tests")
struct HareruyaPriceServiceTests {

    // MARK: - Successful NM Price Parsing

    @Test("Parses NM non-foil price correctly from docs array")
    func parsesNMNonFoilPrice() async throws {
        let httpClient = MockHTTPClient.success(
            data: HareruyaFixtures.nmNonFoilResultJSON,
            url: URL(string: "https://www.hareruyamtg.com/en/products/search/unisearch_api?cardName=Lightning+Bolt")
        )
        let service = HareruyaPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt")

        #expect(price != nil)
        #expect(price?.priceJPY == 110)
        #expect(price?.condition == "NM")
        #expect(price?.isFoil == false)
    }

    // MARK: - Price Formatting

    @Test("Formats price as yen string")
    func formatsPriceAsYen() async throws {
        let httpClient = MockHTTPClient.success(
            data: HareruyaFixtures.nmNonFoilResultJSON,
            url: URL(string: "https://www.hareruyamtg.com/en/products/search/unisearch_api?cardName=Lightning+Bolt")
        )
        let service = HareruyaPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt")

        #expect(price?.formattedPrice == "\u{00A5}110")
    }

    // MARK: - Returns nil When No NM Results

    @Test("Returns nil when only foil NM results exist")
    func returnsNilWhenOnlyFoil() async throws {
        let httpClient = MockHTTPClient.success(
            data: HareruyaFixtures.onlyFoilResultJSON,
            url: URL(string: "https://www.hareruyamtg.com/en/products/search/unisearch_api?cardName=Lightning+Bolt")
        )
        let service = HareruyaPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt")

        #expect(price == nil)
    }

    @Test("Returns nil when no docs in response")
    func returnsNilWhenNoDocs() async throws {
        let httpClient = MockHTTPClient.success(
            data: HareruyaFixtures.noDocsResultJSON,
            url: URL(string: "https://www.hareruyamtg.com/en/products/search/unisearch_api?cardName=Lightning+Bolt")
        )
        let service = HareruyaPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt")

        #expect(price == nil)
    }

    @Test("Returns nil when only SP condition results exist")
    func returnsNilWhenOnlySPCondition() async throws {
        let httpClient = MockHTTPClient.success(
            data: HareruyaFixtures.onlySpConditionJSON,
            url: URL(string: "https://www.hareruyamtg.com/en/products/search/unisearch_api?cardName=Lightning+Bolt")
        )
        let service = HareruyaPriceService(httpClient: httpClient)

        let price = try await service.fetchNMPrice(cardName: "Lightning Bolt")

        #expect(price == nil)
    }

    // MARK: - Network Error

    @Test("Network failure throws NetworkError.networkError")
    func handlesNetworkError() async {
        let httpClient = MockHTTPClient.failure(URLError(.notConnectedToInternet))
        let service = HareruyaPriceService(httpClient: httpClient)

        do {
            _ = try await service.fetchNMPrice(cardName: "Lightning Bolt")
            Issue.record("Expected NetworkError.networkError")
        } catch let error as NetworkError {
            if case .networkError = error {
                // Expected
            } else {
                Issue.record("Expected NetworkError.networkError but got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkError but got \(error)")
        }
    }

    @Test("Malformed JSON throws NetworkError.decodingError")
    func handlesDecodingError() async {
        let httpClient = MockHTTPClient.success(
            data: HareruyaFixtures.malformedJSON,
            url: URL(string: "https://www.hareruyamtg.com/en/products/search/unisearch_api?cardName=Lightning+Bolt")
        )
        let service = HareruyaPriceService(httpClient: httpClient)

        do {
            _ = try await service.fetchNMPrice(cardName: "Lightning Bolt")
            Issue.record("Expected NetworkError.decodingError")
        } catch let error as NetworkError {
            if case .decodingError = error {
                // Expected
            } else {
                Issue.record("Expected NetworkError.decodingError but got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkError but got \(error)")
        }
    }

    // MARK: - URL Encoding

    @Test("Card name is URL-encoded in request")
    func cardNameIsURLEncoded() async throws {
        let capturingClient = CapturingHTTPClient(
            responseData: HareruyaFixtures.noDocsResultJSON,
            statusCode: 200
        )
        let service = HareruyaPriceService(httpClient: capturingClient)

        _ = try? await service.fetchNMPrice(cardName: "Sensei's Divining Top")

        let requestedURL = capturingClient.lastRequest?.url?.absoluteString ?? ""
        #expect(requestedURL.contains("Sensei's%20Divining%20Top") || requestedURL.contains("Sensei%27s%20Divining%20Top"))
        #expect(!requestedURL.contains(" "))
    }

    @Test("Server error throws NetworkError.serverError")
    func handlesServerError() async {
        let httpClient = MockHTTPClient.success(
            data: Data(),
            statusCode: 500,
            url: URL(string: "https://www.hareruyamtg.com/en/products/search/unisearch_api?cardName=Lightning+Bolt")
        )
        let service = HareruyaPriceService(httpClient: httpClient)

        do {
            _ = try await service.fetchNMPrice(cardName: "Lightning Bolt")
            Issue.record("Expected NetworkError.serverError")
        } catch let error as NetworkError {
            if case .serverError = error {
                // Expected
            } else {
                Issue.record("Expected NetworkError.serverError but got \(error)")
            }
        } catch {
            Issue.record("Expected NetworkError but got \(error)")
        }
    }
}
