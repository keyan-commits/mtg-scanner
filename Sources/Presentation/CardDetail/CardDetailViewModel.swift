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

    /// The URL for the card's normal-size image, if available.
    var cardImageURL: URL? {
        guard let urlString = card.imageURIs["normal"] else {
            return nil
        }
        return URL(string: urlString)
    }

    /// A list of key competitive formats paired with their legality status.
    var legalFormats: [(String, LegalityStatus)] {
        let formats = ["standard", "pioneer", "modern", "legacy", "commander"]
        return formats.compactMap { format in
            guard let status = card.legalities.status(for: format) else {
                return nil
            }
            return (format.capitalized, status)
        }
    }
}
