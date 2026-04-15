import Foundation

/// Supported deck formats for the format picker.
/// `freeform` means "no validation" — any card is allowed and no legality
/// banner will be shown in the deck detail screen.
enum DeckFormat: String, CaseIterable, Identifiable {
    case freeform
    case standard
    case pioneer
    case modern
    case legacy
    case vintage
    case pauper
    case commander
    case premodern

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .freeform:  return "Freeform"
        case .standard:  return "Standard"
        case .pioneer:   return "Pioneer"
        case .modern:    return "Modern"
        case .legacy:    return "Legacy"
        case .vintage:   return "Vintage"
        case .pauper:    return "Pauper"
        case .commander: return "Commander"
        case .premodern: return "Premodern"
        }
    }

    /// Scryfall legality dictionary key. Nil for freeform (no validation).
    var scryfallKey: String? {
        switch self {
        case .freeform: return nil
        default:        return rawValue
        }
    }

    /// Minimum legal deck size for this format. Nil = no validation.
    var minDeckSize: Int? {
        switch self {
        case .freeform:  return nil
        case .commander: return 100
        default:         return 60
        }
    }

    /// Maps a stored `DeckList.format` string back to a `DeckFormat` case.
    /// Unknown / legacy values fall back to `.freeform`.
    static func from(stored: String?) -> DeckFormat {
        guard let stored, !stored.isEmpty else { return .freeform }
        let lower = stored.lowercased()
        return DeckFormat(rawValue: lower) ?? .freeform
    }
}
