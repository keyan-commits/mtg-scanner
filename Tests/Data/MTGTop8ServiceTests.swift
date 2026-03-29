import Testing
import Foundation
@testable import MTGCardScanner

@Suite("MTGTop8Service Tests")
struct MTGTop8ServiceTests {

    // MARK: - Test Fixtures

    static let searchResultHTML = """
    <html><body>
    <div class="w_title">105084 decks matching</div>
    <table class="Gen14">
    <tr class="hover_tr">
    <td><a href="event?e=100&d=200&f=MO">Burn</a></td>
    <td>Modern</td>
    <td>Alice Smith</td>
    <td>Pro Tour</td>
    <td>01/01/24</td>
    </tr>
    <tr class="hover_tr">
    <td><a href="event?e=101&d=201&f=MO">Burn</a></td>
    <td>Modern</td>
    <td>Bob Jones</td>
    <td>Grand Prix</td>
    <td>02/01/24</td>
    </tr>
    <tr class="hover_tr">
    <td><a href="event?e=102&d=202&f=LE">Izzet Tempo</a></td>
    <td>Legacy</td>
    <td>Carol White</td>
    <td>Legacy Open</td>
    <td>03/01/24</td>
    </tr>
    <tr class="hover_tr">
    <td><a href="event?e=103&d=203&f=MO">Prowess</a></td>
    <td>Modern</td>
    <td>Dan Black</td>
    <td>Regional</td>
    <td>04/01/24</td>
    </tr>
    </table>
    </body></html>
    """

    static let noResultsHTML = """
    <html><body>
    <div class="w_title">0 deck matching</div>
    <table class="Gen14">
    </table>
    </body></html>
    """

    static let malformedHTML = """
    <html><body>
    <div>Some random content with no deck data</div>
    </body></html>
    """

    // MARK: - Parsing Total Deck Count

    @Test("Parses total deck count from HTML")
    func parsesTotalDeckCount() async throws {
        let data = Data(MTGTop8ServiceTests.searchResultHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Lightning Bolt")

        #expect(result.totalDecks == 105084)
    }

    // MARK: - Archetype Extraction

    @Test("Extracts archetype names from table rows")
    func extractsArchetypeNames() async throws {
        let data = Data(MTGTop8ServiceTests.searchResultHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Lightning Bolt")

        let names = result.topArchetypes.map(\.name)
        #expect(names.contains("Burn"))
        #expect(names.contains("Izzet Tempo"))
        #expect(names.contains("Prowess"))
    }

    @Test("Groups archetypes by name and counts occurrences, sorted by count descending")
    func groupsArchetypesByCount() async throws {
        let data = Data(MTGTop8ServiceTests.searchResultHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Lightning Bolt")

        // Burn appears twice, others once
        #expect(result.topArchetypes.first?.name == "Burn")
        #expect(result.topArchetypes.first?.count == 2)
        #expect(result.topArchetypes.first?.format == "Modern")
    }

    // MARK: - Zero Results

    @Test("Handles zero results gracefully")
    func handlesZeroResults() async throws {
        let data = Data(MTGTop8ServiceTests.noResultsHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Nonexistent Card ZZZZZ")

        #expect(result.totalDecks == 0)
        #expect(result.topArchetypes.isEmpty)
    }

    // MARK: - Network Error

    @Test("Network error throws MTGTop8Error.networkError")
    func networkErrorThrowsNetworkError() async {
        let httpClient = MockHTTPClient.failure(URLError(.notConnectedToInternet))
        let service = MTGTop8Service(httpClient: httpClient)

        do {
            _ = try await service.fetchCardData(name: "Lightning Bolt")
            Issue.record("Expected MTGTop8Error.networkError")
        } catch let error as MTGTop8Error {
            if case .networkError = error {
                // Expected
            } else {
                Issue.record("Expected MTGTop8Error.networkError but got \(error)")
            }
        } catch {
            Issue.record("Expected MTGTop8Error but got \(error)")
        }
    }

    // MARK: - Search URL Construction

    @Test("searchURL is correctly constructed from card name")
    func searchURLConstructedCorrectly() async throws {
        let data = Data(MTGTop8ServiceTests.searchResultHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Lightning Bolt")

        #expect(result.searchURL == "https://mtgtop8.com/search?MD_check=1&SB_check=1&cards=Lightning+Bolt")
    }

    // MARK: - URL Encoding

    @Test("Spaces in card name become + in URL")
    func spacesEncodedAsPlus() async throws {
        let data = Data(MTGTop8ServiceTests.noResultsHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Teferi Time Raveler")

        #expect(result.searchURL == "https://mtgtop8.com/search?MD_check=1&SB_check=1&cards=Teferi+Time+Raveler")
    }

    // MARK: - Card Name Stored

    @Test("Card name is stored in result")
    func cardNameStored() async throws {
        let data = Data(MTGTop8ServiceTests.searchResultHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Lightning Bolt")

        #expect(result.cardName == "Lightning Bolt")
    }

    // MARK: - Format-Specific Search

    @Test("Format-specific search URL includes format code parameter")
    func formatSpecificSearchURLIncludesFormatCode() async throws {
        let data = Data(MTGTop8ServiceTests.searchResultHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Lightning Bolt", format: "MO")

        #expect(result.searchURL == "https://mtgtop8.com/search?MD_check=1&SB_check=1&cards=Lightning+Bolt&format=MO")
    }

    @Test("Format is stored in the returned data")
    func formatStoredInReturnedData() async throws {
        let data = Data(MTGTop8ServiceTests.searchResultHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Lightning Bolt", format: "MO")

        #expect(result.format == "MO")
    }

    @Test("Calling fetchCardData without format returns nil format")
    func noFormatReturnsNilFormat() async throws {
        let data = Data(MTGTop8ServiceTests.searchResultHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        let result = try await service.fetchCardData(name: "Lightning Bolt")

        #expect(result.format == nil)
    }

    // MARK: - Parsing Error

    @Test("Malformed HTML with no deck count throws parsingError")
    func malformedHTMLThrowsParsingError() async {
        let data = Data(MTGTop8ServiceTests.malformedHTML.utf8)
        let httpClient = MockHTTPClient.success(
            data: data,
            url: URL(string: "https://mtgtop8.com/search")
        )
        let service = MTGTop8Service(httpClient: httpClient)

        do {
            _ = try await service.fetchCardData(name: "Lightning Bolt")
            Issue.record("Expected MTGTop8Error.parsingError")
        } catch let error as MTGTop8Error {
            if case .parsingError = error {
                // Expected
            } else {
                Issue.record("Expected MTGTop8Error.parsingError but got \(error)")
            }
        } catch {
            Issue.record("Expected MTGTop8Error but got \(error)")
        }
    }
}
