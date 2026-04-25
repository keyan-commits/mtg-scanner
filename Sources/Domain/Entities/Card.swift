import Foundation

enum CardRarity: String, Sendable, Equatable {
    case common = "common"
    case uncommon = "uncommon"
    case rare = "rare"
    case mythic = "mythic"
}

/// A single Magic card printing.
///
/// Identity is the Scryfall printing UUID (`scryfallID`). Two `Card`
/// values that come from separate fetches of the same printing compare
/// equal and hash equally — historically that wasn't true, because the
/// `id` field was a freshly-minted local UUID and equality used field-
/// by-field synthesis. That made `someList.contains(card)` and
/// `printings.filter { $0.id != current.id }` silently broken.
struct Card: Identifiable, Equatable, Hashable, Sendable {

    /// The Scryfall printing identifier — globally unique per printing.
    /// Acts as both the primary key and the value used for equality and
    /// hashing.
    let scryfallID: String

    let name: String
    let manaCost: String?
    let typeLine: String
    let oracleText: String?
    let set: SetInfo
    let collectorNumber: String
    let rarity: CardRarity
    let artist: String?
    let releasedAt: String?
    let borderColor: String?
    let frame: String?
    /// Scryfall's `frame_effects` array — captures special treatments
    /// like `"borderless"`, `"showcase"`, `"extendedart"`, `"etched"`.
    /// Empty for normal printings. The "First Print (Normal Border)"
    /// strategy filters these out alongside borderless `borderColor`.
    let frameEffects: [String]
    let illustrationID: String?
    let edhrecRank: Int?
    let prices: CardPrices
    let legalities: FormatLegality
    let imageURIs: [String: String]
    let relatedPrintingsURI: String?
    /// Scryfall language code (e.g. "en", "ja", "zhs"). Nil for legacy records.
    let lang: String?
    /// Localized card name as printed (e.g. Japanese name). Nil for English cards.
    let printedName: String?

    // MARK: - Identifiable

    var id: String { scryfallID }

    // MARK: - Equatable / Hashable

    static func == (lhs: Card, rhs: Card) -> Bool {
        lhs.scryfallID == rhs.scryfallID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(scryfallID)
    }

    // MARK: - Display helpers

    /// 4-digit year extracted from `releasedAt` ("2003-10-07" → "2003").
    /// Returns nil if the date is missing or malformed.
    var releaseYear: String? {
        guard let releasedAt, releasedAt.count >= 4 else { return nil }
        let year = String(releasedAt.prefix(4))
        // Sanity check: must be all digits.
        return year.allSatisfy(\.isNumber) ? year : nil
    }

    /// "Onslaught (2003)" — set name with the printing's release year
    /// in parentheses. Falls back to just the set name when no year is
    /// available. Use this anywhere you'd otherwise show `card.set.name`
    /// to a user.
    var setNameWithYear: String {
        if let year = releaseYear {
            return "\(set.name) (\(year))"
        }
        return set.name
    }
}
