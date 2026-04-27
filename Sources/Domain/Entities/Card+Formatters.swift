import SwiftUI

// MARK: - Rarity Formatting

enum RarityFormatter {
    static func label(_ rarity: CardRarity) -> String {
        switch rarity {
        case .mythic: return "Mythic"
        case .rare: return "Rare"
        case .uncommon: return "Uncommon"
        case .common: return "Common"
        }
    }

    static func color(_ rarity: CardRarity) -> Color {
        switch rarity {
        case .mythic: return .orange
        case .rare: return .yellow
        case .uncommon: return .gray
        case .common: return Color(white: 0.5)
        }
    }
}

// MARK: - Legality Formatting

enum LegalityFormatter {
    static func label(_ status: LegalityStatus) -> String {
        switch status {
        case .legal: return "Legal"
        case .banned: return "Banned"
        case .restricted: return "Restricted"
        case .notLegal: return "Not Legal"
        }
    }

    static func color(_ status: LegalityStatus) -> Color {
        switch status {
        case .legal: return .green
        case .banned: return .red
        case .restricted: return .orange
        case .notLegal: return .gray
        }
    }
}

// MARK: - Condition Formatting

enum ConditionFormatter {
    static func color(_ condition: String) -> Color {
        switch condition {
        case "NM": return .green
        case "LP": return .yellow
        case "MP": return .orange
        case "HP", "DMG": return .red
        default: return .gray
        }
    }
}
