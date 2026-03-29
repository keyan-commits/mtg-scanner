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
    /// - Letter suffix in collector number: #38d → "Variant D"
    /// - Cross-reference via illustration_id: 4th Ed #361 shares art with Antiquities #80c → "Variant C"
    var variantLabel: String? {
        let number = card.collectorNumber
        // Check for letter suffix (e.g., "38d", "80a")
        if let lastChar = number.last, lastChar.isLetter {
            return "Variant \(String(lastChar).uppercased())"
        }
        // Will be populated by cross-referencing illustration_id
        return crossReferencedVariant
    }

    /// Variant label derived from illustration_id cross-referencing.
    /// Set externally after async lookup.
    var crossReferencedVariant: String?

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
