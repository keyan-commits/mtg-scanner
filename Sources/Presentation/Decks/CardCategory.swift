import Foundation

/// MTG card categories used to group rows in the deck checklist.
/// Order matches the conventional MTG deck list (Creatures first, Lands last).
enum CardCategory: String, CaseIterable {
    case commander = "Commander"
    case creatures = "Creatures"
    case planeswalkers = "Planeswalkers"
    case instants = "Instants"
    case sorceries = "Sorceries"
    case artifacts = "Artifacts"
    case enchantments = "Enchantments"
    case lands = "Lands"
    case other = "Other"

    /// Sort priority — lower comes first.
    var sortOrder: Int {
        switch self {
        case .commander: return 0
        case .creatures: return 1
        case .planeswalkers: return 2
        case .instants: return 3
        case .sorceries: return 4
        case .artifacts: return 5
        case .enchantments: return 6
        case .lands: return 7
        case .other: return 8
        }
    }

    /// Buckets a typeLine string (e.g. "Legendary Creature — Human Wizard")
    /// into a category. Falls back to .other when the typeLine is missing.
    static func from(typeLine: String?) -> CardCategory {
        guard let line = typeLine?.lowercased() else { return .other }
        // Check most specific types first — a "Legendary Creature - Land" is a Creature
        if line.contains("creature") { return .creatures }
        if line.contains("planeswalker") { return .planeswalkers }
        if line.contains("instant") { return .instants }
        if line.contains("sorcery") { return .sorceries }
        if line.contains("enchantment") { return .enchantments }
        if line.contains("artifact") { return .artifacts }
        if line.contains("land") { return .lands }
        return .other
    }
}
