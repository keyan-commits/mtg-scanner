import Foundation

// MARK: - Hareruya Price Model

struct HareruyaPrice: Sendable {
    let priceJPY: Int
    let condition: String
    let isFoil: Bool
    let formattedPrice: String
}

// MARK: - Hareruya Response DTOs

private struct HareruyaResponseDTO: Decodable {
    let response: HareruyaResponseBodyDTO
}

private struct HareruyaResponseBodyDTO: Decodable {
    let numFound: Int
    let docs: [HareruyaDocDTO]
}

private struct HareruyaDocDTO: Decodable {
    let name: String?
    let price: String
    let cardCondition: Int
    let foilFlg: Int

    enum CodingKeys: String, CodingKey {
        case name
        case price
        case cardCondition = "card_condition"
        case foilFlg = "foil_flg"
    }
}

// MARK: - Protocol

protocol HareruyaPriceServiceProtocol: Sendable {
    func fetchNMPrice(cardName: String) async throws -> HareruyaPrice?
}

// MARK: - Implementation

struct HareruyaPriceService: HareruyaPriceServiceProtocol {
    private let baseURL = "https://www.hareruyamtg.com/en/products/search/unisearch_api"
    private let httpClient: HTTPClientProtocol
    private let decoder: JSONDecoder

    init(httpClient: HTTPClientProtocol = URLSessionHTTPClient()) {
        self.httpClient = httpClient
        self.decoder = JSONDecoder()
    }

    func fetchNMPrice(cardName: String) async throws -> HareruyaPrice? {
        guard let encodedName = cardName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw NetworkError.networkError("Invalid card name encoding")
        }

        let urlString = "\(baseURL)?cardName=\(encodedName)"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
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

        let dto: HareruyaResponseDTO
        do {
            dto = try decoder.decode(HareruyaResponseDTO.self, from: data)
        } catch {
            throw NetworkError.decodingError(error.localizedDescription)
        }

        // Filter for NM (card_condition == 1) and non-foil (foil_flg == 0)
        guard let match = dto.response.docs.first(where: {
            $0.cardCondition == 1 && $0.foilFlg == 0
        }) else {
            return nil
        }

        guard let priceInt = Int(match.price) else {
            return nil
        }

        return HareruyaPrice(
            priceJPY: priceInt,
            condition: "NM",
            isFoil: false,
            formattedPrice: "\u{00A5}\(priceInt)"
        )
    }
}
