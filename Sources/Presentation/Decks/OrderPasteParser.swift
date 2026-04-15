import Foundation

/// Stateless parser for seller order confirmation paste-ins.
/// Used by `MarkOrderReceivedSheet`. Extracted so it can be unit-tested
/// independently of any SwiftUI view.
enum OrderPasteParser {

    /// One parsed line: quantity, card name, optional set + variant + price.
    struct ParsedLine: Equatable {
        let quantity: Int
        let name: String
        let setCode: String?
        let variant: String?
        let pricePerCard: Double?
    }

    /// Parses a multi-line paste. Skips headers, totals, blank lines, and
    /// section markers like `<White>`. Returns one entry per parseable line.
    static func parse(_ text: String) -> [ParsedLine] {
        let normalized = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        var out: [ParsedLine] = []
        for raw in normalized.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if shouldSkip(trimmed) { continue }
            if let line = parseLine(trimmed) {
                out.append(line)
            }
        }
        return out
    }

    /// True for lines we should ignore entirely (headers, totals, section markers).
    static func shouldSkip(_ line: String) -> Bool {
        let lower = line.lowercased()
        let prefixes = ["total", "details", "confirmed", "paid", "eta", "shipping", "subtotal", "tax", "//"]
        if prefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        // Color section headers like "<White>", "<Black>" — single token wrapped in <>
        if line.hasPrefix("<") && line.hasSuffix(">") && !line.contains(" ") { return true }
        return false
    }

    /// Parses one line: `<qty> <name> [<set>] [<variant>] = <price>[ea][, junk]`.
    /// Trailing price is optional. Set/variant are optional. Anything after
    /// the price (e.g. `, Card Kingdom` or other free-form notes) is tolerated
    /// and discarded.
    static func parseLine(_ line: String) -> ParsedLine? {
        var rest = line

        // Trailing metadata: everything from the first `=` to end of line is
        // treated as "this is just trailing info." We pull the first numeric
        // value out as the price and discard the rest.
        var price: Double?
        if let eqIdx = rest.firstIndex(of: "=") {
            let metadata = String(rest[rest.index(after: eqIdx)...])
            rest = String(rest[..<eqIdx])
            if let priceRegex = try? NSRegularExpression(pattern: #"([0-9]+(?:[.,][0-9]+)?)"#),
               let match = priceRegex.firstMatch(in: metadata, range: NSRange(metadata.startIndex..., in: metadata)),
               let priceRange = Range(match.range(at: 1), in: metadata) {
                let raw = metadata[priceRange].replacingOccurrences(of: ",", with: ".")
                price = Double(raw)
            }
        }

        // Quantity at the start
        let qtyPattern = #"^\s*(\d+)\s*[xX]?\s+(.+)$"#
        guard let qtyRegex = try? NSRegularExpression(pattern: qtyPattern),
              let match = qtyRegex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
              let qtyRange = Range(match.range(at: 1), in: rest),
              let restRange = Range(match.range(at: 2), in: rest),
              let qty = Int(rest[qtyRange]) else {
            return nil
        }
        rest = String(rest[restRange])

        // Set code in [...]
        var setCode: String?
        if let setRegex = try? NSRegularExpression(pattern: #"\[([A-Za-z0-9]+)\]"#),
           let setMatch = setRegex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
           let codeRange = Range(setMatch.range(at: 1), in: rest),
           let fullRange = Range(setMatch.range, in: rest) {
            setCode = String(rest[codeRange]).lowercased()
            rest.removeSubrange(fullRange)
        }

        // Variant in <...>
        var variant: String?
        if let varRegex = try? NSRegularExpression(pattern: #"<([^>]+)>"#),
           let varMatch = varRegex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
           let valRange = Range(varMatch.range(at: 1), in: rest),
           let fullRange = Range(varMatch.range, in: rest) {
            variant = String(rest[valRange])
            rest.removeSubrange(fullRange)
        }

        // Strip trailing Wizards-style parenthetical set codes + collector
        // numbers, e.g. "(M11) 146". Tolerated so deck import paste-ins from
        // tools like Moxfield work without preprocessing.
        if let parenRegex = try? NSRegularExpression(pattern: #"\([^)]*\)\s*\S*"#) {
            let nsr = NSRange(rest.startIndex..., in: rest)
            rest = parenRegex.stringByReplacingMatches(in: rest, range: nsr, withTemplate: "")
        }

        let name = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return ParsedLine(quantity: qty, name: name, setCode: setCode, variant: variant, pricePerCard: price)
    }
}
