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
}
