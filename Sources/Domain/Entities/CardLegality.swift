import Foundation

enum LegalityStatus: String, Sendable, Equatable {
    case legal = "legal"
    case notLegal = "not_legal"
    case banned = "banned"
    case restricted = "restricted"
}

struct FormatLegality: Equatable, Sendable {
    private let statuses: [String: LegalityStatus]

    init(_ statuses: [String: LegalityStatus]) {
        self.statuses = statuses
    }

    func isLegal(in format: String) -> Bool {
        statuses[format] == .legal
    }

    func status(for format: String) -> LegalityStatus? {
        statuses[format]
    }

    var allFormats: [String] {
        Array(statuses.keys)
    }

    /// Short summary of format legality for AI prompts.
    var summary: String {
        let legal = statuses.filter { $0.value == .legal }.keys.sorted()
        if legal.isEmpty { return "Not legal in any format" }
        return legal.joined(separator: ", ")
    }

    /// Detailed legality including bans for AI prompts.
    var detailedSummary: String {
        let legal = statuses.filter { $0.value == .legal }.keys.sorted()
        let banned = statuses.filter { $0.value == .banned }.keys.sorted()
        let restricted = statuses.filter { $0.value == .restricted }.keys.sorted()
        var parts: [String] = []
        if !legal.isEmpty { parts.append("Legal: \(legal.joined(separator: ", "))") }
        if !banned.isEmpty { parts.append("BANNED: \(banned.joined(separator: ", "))") }
        if !restricted.isEmpty { parts.append("Restricted: \(restricted.joined(separator: ", "))") }
        return parts.isEmpty ? "Not legal in any format" : parts.joined(separator: ". ")
    }
}
