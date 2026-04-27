import Testing
import Foundation
@testable import MTGCardScanner

@Suite("MTGStocks Interests Filtering Tests")
struct MTGStocksInterestsFilterTests {

    // MARK: - Helpers

    /// Simulates the filtering logic from MTGStocksService.fetchInterests()
    /// against raw JSON entries, returning the filtered and deduplicated results.
    private static func filterInterests(_ rawInterests: [[String: Any]]) -> [MTGStocksInterest] {
        let interests = rawInterests.compactMap { entry -> MTGStocksInterest? in
            guard let printObj = entry["print"] as? [String: Any],
                  let id = printObj["id"] as? Int,
                  let name = printObj["name"] as? String else { return nil }
            let isTournamentLegal = printObj["tournamentLegal"] as? Bool ?? false
            guard isTournamentLegal else { return nil }
            let setType = printObj["set_type"] as? String ?? ""
            let skipSetTypes: Set<String> = ["art_series", "token", "memorabilia", "minigame"]
            guard !skipSetTypes.contains(setType) else { return nil }
            guard !name.contains("Art Card") else { return nil }
            let currentPrice = entry["present_price"] as? Double
            let previousPrice = entry["past_price"] as? Double
            let pct = entry["percentage"] as? Double
            guard let current = currentPrice, current >= 2.0,
                  let previous = previousPrice, previous >= 1.0 else { return nil }
            guard let percent = pct, abs(percent) <= 500 else { return nil }
            let setName = printObj["set_name"] as? String
            let setCode = printObj["set_code"] as? String
            return MTGStocksInterest(
                id: id, name: name, setName: setName, setCode: setCode,
                currentPrice: current, previousPrice: previous,
                percentageChange: percent
            )
        }

        var bestByName: [String: MTGStocksInterest] = [:]
        for interest in interests {
            let key = interest.name.lowercased()
            if let existing = bestByName[key] {
                let existingDelta = abs((existing.currentPrice ?? 0) - (existing.previousPrice ?? 0))
                let newDelta = abs((interest.currentPrice ?? 0) - (interest.previousPrice ?? 0))
                if newDelta > existingDelta { bestByName[key] = interest }
            } else {
                bestByName[key] = interest
            }
        }

        return bestByName.values
            .sorted { abs($0.percentageChange ?? 0) > abs($1.percentageChange ?? 0) }
    }

    private static func makeEntry(
        id: Int = 1,
        name: String = "Lightning Bolt",
        tournamentLegal: Bool = true,
        setType: String = "expansion",
        currentPrice: Double = 5.0,
        previousPrice: Double = 3.0,
        percentage: Double = 66.7,
        setName: String? = "Masters 25",
        setCode: String? = "a25"
    ) -> [String: Any] {
        var printObj: [String: Any] = [
            "id": id,
            "name": name,
            "tournamentLegal": tournamentLegal,
            "set_type": setType
        ]
        if let setName { printObj["set_name"] = setName }
        if let setCode { printObj["set_code"] = setCode }
        return [
            "print": printObj,
            "present_price": currentPrice,
            "past_price": previousPrice,
            "percentage": percentage
        ]
    }

    // MARK: - Tournament Legal Filter

    @Test("Filters out non-tournament-legal cards")
    func filterNonTournamentLegal() {
        let entries = [
            Self.makeEntry(name: "Lightning Bolt", tournamentLegal: true),
            Self.makeEntry(id: 2, name: "Art Token", tournamentLegal: false)
        ]
        let result = Self.filterInterests(entries)
        #expect(result.count == 1)
        #expect(result[0].name == "Lightning Bolt")
    }

    // MARK: - Set Type Filter

    @Test("Filters out art_series, token, memorabilia, minigame set types")
    func filterSetTypes() {
        let entries = [
            Self.makeEntry(name: "Real Card", setType: "expansion"),
            Self.makeEntry(id: 2, name: "Art Card Thing", setType: "art_series"),
            Self.makeEntry(id: 3, name: "Token Card", setType: "token"),
            Self.makeEntry(id: 4, name: "Memorabilia", setType: "memorabilia"),
            Self.makeEntry(id: 5, name: "Mini Game", setType: "minigame")
        ]
        let result = Self.filterInterests(entries)
        #expect(result.count == 1)
        #expect(result[0].name == "Real Card")
    }

    @Test("Filters out cards with 'Art Card' in name")
    func filterArtCardName() {
        let entries = [
            Self.makeEntry(name: "Lightning Bolt Art Card", setType: "expansion")
        ]
        let result = Self.filterInterests(entries)
        #expect(result.isEmpty)
    }

    // MARK: - Price Threshold Filter

    @Test("Filters out cards below $2 current price")
    func filterBelowPriceFloor() {
        let entries = [
            Self.makeEntry(name: "Cheap Card", currentPrice: 1.99, previousPrice: 1.5, percentage: 32.7)
        ]
        let result = Self.filterInterests(entries)
        #expect(result.isEmpty)
    }

    @Test("Keeps cards at exactly $2 current price")
    func keepAtPriceFloor() {
        let entries = [
            Self.makeEntry(name: "Boundary Card", currentPrice: 2.0, previousPrice: 1.5, percentage: 33.3)
        ]
        let result = Self.filterInterests(entries)
        #expect(result.count == 1)
    }

    @Test("Filters out cards below $1 previous price")
    func filterBelowPreviousPriceFloor() {
        let entries = [
            Self.makeEntry(name: "Spike Card", currentPrice: 5.0, previousPrice: 0.99, percentage: 400.0)
        ]
        let result = Self.filterInterests(entries)
        #expect(result.isEmpty)
    }

    // MARK: - Percentage Cap

    @Test("Filters out cards with percentage change above 500%")
    func filterAbovePercentageCap() {
        let entries = [
            Self.makeEntry(name: "Glitchy Card", currentPrice: 60.0, previousPrice: 1.0, percentage: 5900.0)
        ]
        let result = Self.filterInterests(entries)
        #expect(result.isEmpty)
    }

    @Test("Keeps cards at exactly 500% change")
    func keepAtPercentageCap() {
        let entries = [
            Self.makeEntry(name: "Big Mover", currentPrice: 12.0, previousPrice: 2.0, percentage: 500.0)
        ]
        let result = Self.filterInterests(entries)
        #expect(result.count == 1)
    }

    @Test("Filters negative percentage beyond -500%")
    func filterNegativePercentageCap() {
        let entries = [
            Self.makeEntry(name: "Crash Card", currentPrice: 2.0, previousPrice: 50.0, percentage: -501.0)
        ]
        let result = Self.filterInterests(entries)
        #expect(result.isEmpty)
    }

    // MARK: - Dedup by Name

    @Test("Deduplicates by card name keeping highest absolute price change")
    func dedupByName() {
        let entries = [
            Self.makeEntry(id: 1, name: "Lightning Bolt", currentPrice: 5.0, previousPrice: 3.0, percentage: 66.7, setCode: "a25"),
            Self.makeEntry(id: 2, name: "Lightning Bolt", currentPrice: 8.0, previousPrice: 2.0, percentage: 300.0, setCode: "m25")
        ]
        let result = Self.filterInterests(entries)
        #expect(result.count == 1)
        // Should keep the one with bigger absolute delta ($6 vs $2)
        #expect(result[0].id == 2)
    }

    @Test("Dedup is case-insensitive")
    func dedupCaseInsensitive() {
        let entries = [
            Self.makeEntry(id: 1, name: "Lightning Bolt", currentPrice: 5.0, previousPrice: 3.0, percentage: 66.7),
            Self.makeEntry(id: 2, name: "lightning bolt", currentPrice: 10.0, previousPrice: 2.0, percentage: 400.0)
        ]
        let result = Self.filterInterests(entries)
        #expect(result.count == 1)
    }

    // MARK: - Valid Entry Passes All Filters

    @Test("Valid entry passes all filters")
    func validEntryPasses() {
        let entries = [
            Self.makeEntry(
                name: "Ragavan, Nimble Pilferer",
                tournamentLegal: true,
                setType: "expansion",
                currentPrice: 65.0,
                previousPrice: 55.0,
                percentage: 18.2
            )
        ]
        let result = Self.filterInterests(entries)
        #expect(result.count == 1)
        #expect(result[0].name == "Ragavan, Nimble Pilferer")
        #expect(result[0].currentPrice == 65.0)
        #expect(result[0].previousPrice == 55.0)
    }

    // MARK: - Sorting

    @Test("Results sorted by absolute percentage descending")
    func sortedByPercentage() {
        let entries = [
            Self.makeEntry(id: 1, name: "Small Mover", currentPrice: 3.0, previousPrice: 2.5, percentage: 20.0),
            Self.makeEntry(id: 2, name: "Big Mover", currentPrice: 10.0, previousPrice: 2.0, percentage: 400.0),
            Self.makeEntry(id: 3, name: "Medium Mover", currentPrice: 5.0, previousPrice: 3.0, percentage: 66.7)
        ]
        let result = Self.filterInterests(entries)
        #expect(result.count == 3)
        #expect(result[0].name == "Big Mover")
        #expect(result[1].name == "Medium Mover")
        #expect(result[2].name == "Small Mover")
    }
}
