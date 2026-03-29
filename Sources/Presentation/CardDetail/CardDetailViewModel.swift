import Foundation
import Observation

// MARK: - Card Detail View Model

/// Provides computed presentation data for a single Magic card.
@Observable
final class CardDetailViewModel {

    // MARK: - Properties

    let card: Card

    // MARK: - Initialization

    init(card: Card) {
        self.card = card
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
            // Check for well-known named variants
            if let namedVariants = Self.knownVariantNames[card.name],
               let name = namedVariants[suffix] {
                return name
            }
            return "Variant \(suffix.uppercased())"
        }
        return crossReferencedVariant
    }

    /// Variant label derived from illustration_id cross-referencing.
    var crossReferencedVariant: String?

    /// Well-known variant names from community conventions.
    private static let knownVariantNames: [String: [String: String]] = [
        "Mishra's Factory": ["a": "Spring", "b": "Summer", "c": "Autumn", "d": "Winter"],
        "Urza's Mine": ["a": "Pulley", "b": "Mouth", "c": "Derrick", "d": "Tower"],
        "Urza's Power Plant": ["a": "Bug", "b": "Columns", "c": "Sphere", "d": "Rock in Eye"],
        "Urza's Tower": ["a": "Forest", "b": "Mountains", "c": "Plains", "d": "Shore"],
        "Strip Mine": ["a": "Tower", "b": "No Horizon", "c": "Uneven Horizon", "d": "Even Horizon"],
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
