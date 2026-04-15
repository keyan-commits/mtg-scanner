import SwiftUI

/// Renders a Magic: The Gathering mana cost (e.g., "{1}{W}{W}") as a row of
/// official mana symbol images loaded from Wizards' Gatherer CDN.
struct ManaCostView: View {

    let cost: String
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(parseSymbols(cost).enumerated()), id: \.offset) { _, token in
                ManaSymbolView(token: token, size: size)
            }
        }
    }

    /// Splits a Scryfall mana cost like "{1}{W}{U}" into ["1", "W", "U"].
    private func parseSymbols(_ cost: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inside = false
        for ch in cost {
            if ch == "{" { inside = true; current = ""; continue }
            if ch == "}" { inside = false; if !current.isEmpty { result.append(current) }; continue }
            if inside { current.append(ch) }
        }
        return result
    }
}

/// A single mana symbol rendered from a bundled vector PDF asset.
/// Falls back to a gray placeholder if the asset is missing.
struct ManaSymbolView: View {
    let token: String
    var size: CGFloat = 14

    var body: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.25))
            .overlay(
                Text(token)
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.secondary)
            )
            .frame(width: size, height: size)
    }

    /// Returns the asset catalog name for the bundled mana PDF, or nil if unsupported.
    private var assetName: String? {
        // Hybrid mana like "W/U" → no asset, fall back to placeholder
        guard !token.contains("/") else { return nil }
        let normalized = token.uppercased()
        let supported: Set<String> = [
            "W", "U", "B", "R", "G", "C", "S", "T", "X",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15"
        ]
        guard supported.contains(normalized) else { return nil }
        return "Mana\(normalized)"
    }
}
