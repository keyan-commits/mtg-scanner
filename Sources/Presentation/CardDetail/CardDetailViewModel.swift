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
