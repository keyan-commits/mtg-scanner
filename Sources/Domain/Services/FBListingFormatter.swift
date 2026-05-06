import Foundation

// Builds the Facebook sale-post text the user posts to the MTG Keyan
// page. Format mirrors the user's hand-typed posts:
//
//   📣📣📣📣📣📣📣📣Selling📣📣📣📣📣📣📣📣
//   ✅1x Watery Grave [RAV] [FOIL] [OG] = 9k
//   ✅1x Underground River [10E] [FOIL] = 2k
//   <footer>
//
// All resolution (OG flag, price source, currency conversion) is the
// caller's responsibility — this enum is a pure string builder so the
// formatting logic can be unit-tested without async lookups.
enum FBListingFormatter {

    /// One ✅ line in the post. Caller splits foil + nonfoil legs of
    /// the same card into separate specs.
    struct LineSpec: Equatable {
        let quantity: Int
        let cardName: String
        let setCode: String
        let isFoil: Bool
        let isOriginalPrinting: Bool
        /// Price in USD. Caller picks: TCG Mid for nonfoil, foil
        /// market for foil. nil if no price is available.
        let priceUSD: Double?
    }

    static let header = "📣📣📣📣📣📣📣📣Selling📣📣📣📣📣📣📣📣"

    /// Default footer the user has been pasting verbatim. Made an
    /// editable string so future Settings can override it without
    /// touching the formatter.
    static let defaultFooter = """
🛖 Location: Ortigas / Pasig
💲 Mode of Payment: GCash, Bank Transfer
📦 Delivery: Grab / Lalamove (buyer's expense)
👬 Meetups (by schedule): SM Megamall
💻 For more photos or videos, feel free to send a PM
"""

    /// Format USD as the precise PHP integer with thousand separators
    /// (e.g. `9,665`, `1,950`). Caller is the one posting to FB and
    /// often rounds in their head ("call it 9k"); the formatter just
    /// does the math. Returns "?" when price or rate is missing.
    static func formatPricePHK(usd: Double?, usdToPHP: Double) -> String {
        guard let usd, usd > 0, usdToPHP > 0 else { return "?" }
        let php = (usd * usdToPHP).rounded()
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: php)) ?? String(Int(php))
    }

    /// Render a single ✅ line. Tags follow the user's order:
    /// `[SET] [FOIL]? [OG]?`.
    static func formatLine(_ spec: LineSpec, usdToPHP: Double) -> String {
        var tags: [String] = ["[\(spec.setCode.uppercased())]"]
        if spec.isFoil { tags.append("[FOIL]") }
        if spec.isOriginalPrinting { tags.append("[OG]") }
        let price = formatPricePHK(usd: spec.priceUSD, usdToPHP: usdToPHP)
        return "✅\(spec.quantity)x \(spec.cardName) \(tags.joined(separator: " ")) = \(price)"
    }

    /// Full post: header + ✅ lines + footer.
    static func formatPost(
        lines: [LineSpec],
        usdToPHP: Double,
        footer: String = defaultFooter
    ) -> String {
        let body = lines.map { formatLine($0, usdToPHP: usdToPHP) }.joined(separator: "\n")
        return "\(header)\n\(body)\n\(footer)"
    }

    /// Returns true when `item.setCode` matches the earliest-released
    /// printing across `printings` (i.e. this is the [OG] set). Compares
    /// `releasedAt` ISO strings lexicographically — the same approach
    /// `PrintingStrategy` uses for "First Print" elsewhere.
    static func isOriginalPrinting(setCode: String, printings: [Card]) -> Bool {
        guard !printings.isEmpty else { return false }
        let earliest = printings.min { (a, b) -> Bool in
            (a.releasedAt ?? "9999") < (b.releasedAt ?? "9999")
        }
        return earliest?.set.code.lowercased() == setCode.lowercased()
    }
}
