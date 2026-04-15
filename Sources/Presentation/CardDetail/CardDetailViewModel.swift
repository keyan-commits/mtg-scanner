import Foundation
import Observation

// MARK: - Card Detail View Model

/// Provides computed presentation data for a single Magic card.
@Observable
final class CardDetailViewModel {

    // MARK: - Properties

    /// The currently displayed card. Mutable so the detail screen can
    /// swap to a different printing in-place when the user taps the
    /// "Other Printings" section, instead of stacking new sheets/screens.
    var card: Card

    // MARK: - Initialization

    init(card: Card) {
        self.card = card
    }

    /// Swaps the displayed card. Resets transient state (variant
    /// cross-reference) so it gets recomputed for the new printing.
    func swap(to newCard: Card) {
        self.card = newCard
        self.crossReferencedVariant = nil
    }

    // MARK: - Computed Properties

    /// The card's display price, preferring USD over EUR.
    var formattedPrice: String? {
        if let usd = card.prices.usd {
            return "$\(usd)"
        }
        if let eur = card.prices.eur {
            return "\u{20AC}\(eur)"
        }
        return nil
    }

    /// The source of the displayed price.
    var priceSource: String {
        if card.prices.usd != nil {
            return "Source: TCGPlayer via Scryfall"
        }
        if card.prices.eur != nil {
            return "Source: Cardmarket via Scryfall"
        }
        return ""
    }

    /// The URL for the card's normal-size image, if available.
    var cardImageURL: URL? {
        guard let urlString = card.imageURIs["normal"] else {
            return nil
        }
        return URL(string: urlString)
    }

    /// The art variant label.
    /// - Named variants: Mishra's Factory #80a → "Spring"
    /// - Letter suffix fallback: #38d → "Variant D"
    /// - Cross-reference via illustration_id for reprints
    var variantLabel: String? {
        let number = card.collectorNumber
        if let lastChar = number.last, lastChar.isLetter {
            let suffix = String(lastChar).lowercased()
            // Check for well-known descriptive names (Antiquities lands)
            if let namedVariants = Self.knownVariantNames[card.name],
               let name = namedVariants[suffix] {
                return name
            }
            // For other multi-art cards (Fallen Empires, etc.), use artist name
            // since that's how the community identifies them
            if let artist = card.artist {
                // Extract last name for brevity
                let parts = artist.split(separator: " ")
                if let lastName = parts.last {
                    return String(lastName)
                }
            }
            return "Variant \(suffix.uppercased())"
        }
        return crossReferencedVariant
    }

    /// Variant label derived from illustration_id cross-referencing.
    var crossReferencedVariant: String?

    /// Well-known variant names from community/retailer conventions.
    /// Only the 5 Antiquities lands have descriptive scene names.
    private static let knownVariantNames: [String: [String: String]] = [
        // Antiquities — descriptive scene names (used by TCGPlayer, Card Kingdom, SCG)
        "Mishra's Factory": ["a": "Spring", "b": "Summer", "c": "Autumn", "d": "Winter"],
        "Urza's Mine": ["a": "Pulley", "b": "Mouth", "c": "Clawed Sphere", "d": "Tower"],
        "Urza's Power Plant": ["a": "Sphere", "b": "Columns", "c": "Bug", "d": "Rock in Pot"],
        "Urza's Tower": ["a": "Forest", "b": "Shore", "c": "Plains", "d": "Mountains"],
        "Strip Mine": ["a": "No Horizon", "b": "Even Horizon", "c": "Tower", "d": "Uneven Horizon"],
    ]

    /// The artist attribution line.
    var artistLabel: String? {
        card.artist.map { "Art by \($0)" }
    }

    /// A list of formats paired with their legality status.
    var legalFormats: [(String, LegalityStatus)] {
        let formats: [(key: String, display: String)] = [
            ("standard", "Standard"),
            ("pioneer", "Pioneer"),
            ("modern", "Modern"),
            ("legacy", "Legacy"),
            ("vintage", "Vintage"),
            ("pauper", "Pauper"),
            ("premodern", "Premodern"),
            ("commander", "Commander"),
            ("duel", "Duel Commander"),
            ("oldschool", "Old School 93/94"),
        ]
        return formats.compactMap { format in
            guard let status = card.legalities.status(for: format.key) else {
                return nil
            }
            return (format.display, status)
        }
    }
}
