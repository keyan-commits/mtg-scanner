import Foundation

// MARK: - Card Kingdom Price Model

struct CardKingdomPrice: Sendable {
    let retailUSD: Double?
    let buylistUSD: Double?
    let formattedRetail: String?
    let formattedBuylist: String?
}

// MARK: - Card Kingdom Response DTOs

private struct CardKingdomResponseDTO: Decodable {
    let meta: CardKingdomMetaDTO?
    let data: [CardKingdomItemDTO]
}

private struct CardKingdomMetaDTO: Decodable {
    let date: String?
    let version: String?
}

private struct CardKingdomItemDTO: Decodable {
    let id: Int?
    let name: String
    let edition: String
    let sku: String?
    let priceRetail: Double
    let priceBuy: Double
    let qtyRetail: Int?
    let qtyBuy: Int?
    let condition: String?
    let isFoil: Bool
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case edition
        case sku
        case priceRetail = "price_retail"
        case priceBuy = "price_buy"
        case qtyRetail = "qty_retail"
        case qtyBuy = "qty_buy"
        case condition
        case isFoil = "is_foil"
        case url
    }
}

// MARK: - Protocol

protocol CardKingdomPriceServiceProtocol: Sendable {
    func fetchNMPrice(cardName: String, setName: String) async throws -> CardKingdomPrice?
}

// MARK: - Implementation

struct CardKingdomPriceService: CardKingdomPriceServiceProtocol {
    private let priceListURL = "https://api.cardkingdom.com/api/pricelist"
    private let httpClient: HTTPClientProtocol
    private let decoder: JSONDecoder

    init(httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.httpClient = httpClient
        self.decoder = JSONDecoder()
    }

    func fetchNMPrice(cardName: String, setName: String) async throws -> CardKingdomPrice? {
        guard let url = URL(string: priceListURL) else {
            throw NetworkError.invalidURL(priceListURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw NetworkError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.networkError("Invalid response type")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }

        let dto: CardKingdomResponseDTO
        do {
            dto = try decoder.decode(CardKingdomResponseDTO.self, from: data)
        } catch {
            throw NetworkError.decodingError(error.localizedDescription)
        }

        // Search for matching card: name + set, NM condition, non-foil
        let searchName = cardName.lowercased()
        let searchSet = setName.lowercased()

        guard let match = dto.data.first(where: { item in
            item.name.lowercased() == searchName
            && item.edition.lowercased() == searchSet
            && !item.isFoil
            && (item.condition?.uppercased() == "NM" || item.condition == nil)
        }) else {
            return nil
        }

        return CardKingdomPrice(
            retailUSD: match.priceRetail,
            buylistUSD: match.priceBuy,
            formattedRetail: formatUSD(match.priceRetail),
            formattedBuylist: formatUSD(match.priceBuy)
        )
    }

    // MARK: - Private Helpers

    private func formatUSD(_ amount: Double) -> String {
        return String(format: "$%.2f", amount)
    }
}
