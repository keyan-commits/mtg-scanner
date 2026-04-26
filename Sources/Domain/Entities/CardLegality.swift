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
}
