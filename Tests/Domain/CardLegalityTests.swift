import Testing
import Foundation
@testable import MTGCardScanner

@Suite("CardLegality Tests")
struct CardLegalityTests {

    private static func makeLegality(_ statuses: [String: LegalityStatus]) -> FormatLegality {
        FormatLegality(statuses)
    }

    // MARK: - isLegal

    @Test("isLegal returns true for legal format")
    func isLegalTrue() {
        let legality = Self.makeLegality(["modern": .legal, "standard": .banned])
        #expect(legality.isLegal(in: "modern") == true)
    }

    @Test("isLegal returns false for banned format")
    func isLegalFalseBanned() {
        let legality = Self.makeLegality(["modern": .banned])
        #expect(legality.isLegal(in: "modern") == false)
    }

    @Test("isLegal returns false for unknown format")
    func isLegalFalseUnknown() {
        let legality = Self.makeLegality(["modern": .legal])
        #expect(legality.isLegal(in: "vintage") == false)
    }

    // MARK: - status

    @Test("status returns correct status")
    func statusReturns() {
        let legality = Self.makeLegality(["legacy": .restricted])
        #expect(legality.status(for: "legacy") == .restricted)
    }

    @Test("status returns nil for unknown format")
    func statusNil() {
        let legality = Self.makeLegality(["modern": .legal])
        #expect(legality.status(for: "pioneer") == nil)
    }

    // MARK: - summary

    @Test("summary lists legal formats sorted")
    func summaryLegal() {
        let legality = Self.makeLegality([
            "modern": .legal,
            "legacy": .legal,
            "standard": .banned
        ])
        #expect(legality.summary == "legacy, modern")
    }

    @Test("summary returns not legal message when empty")
    func summaryEmpty() {
        let legality = Self.makeLegality(["modern": .banned, "legacy": .notLegal])
        #expect(legality.summary == "Not legal in any format")
    }

    // MARK: - detailedSummary

    @Test("detailedSummary includes all sections")
    func detailedSummaryAll() {
        let legality = Self.makeLegality([
            "modern": .legal,
            "legacy": .banned,
            "vintage": .restricted
        ])
        let summary = legality.detailedSummary
        #expect(summary.contains("Legal: modern"))
        #expect(summary.contains("BANNED: legacy"))
        #expect(summary.contains("Restricted: vintage"))
    }

    @Test("detailedSummary handles all not legal")
    func detailedSummaryNone() {
        let legality = Self.makeLegality(["modern": .notLegal])
        #expect(legality.detailedSummary == "Not legal in any format")
    }
}
