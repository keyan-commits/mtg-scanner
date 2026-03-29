import Foundation

// MARK: - Scryfall Search Result DTO

struct ScryfallSearchDTO: Codable, Sendable {
    let object: String
    let totalCards: Int
    let hasMore: Bool
    let nextPage: String?
    let data: [ScryfallCardDTO]

    enum CodingKeys: String, CodingKey {
        case object, data
        case totalCards = "total_cards"
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}
