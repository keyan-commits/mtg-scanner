import Foundation

// MARK: - Hareruya Price Model

struct HareruyaPrice: Sendable {
    let priceJPY: Int
    let condition: String
    let isFoil: Bool
    let formattedPrice: String
}

// MARK: - Hareruya Error

enum HareruyaError: Error, Equatable, Sendable {
    case networkError(String)
    case serverError(statusCode: Int)
    case decodingError(String)

    static func == (lhs: HareruyaError, rhs: HareruyaError) -> Bool {
        switch (lhs, rhs) {
        case (.networkError(let l), .networkError(let r)):
            return l == r
        case (.serverError(let l), .serverError(let r)):
            return l == r
        case (.decodingError(let l), .decodingError(let r)):
            return l == r
        default:
            return false
        }
    }
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
            throw HareruyaError.networkError("Invalid card name encoding")
        }

        let url = URL(string: "\(baseURL)?cardName=\(encodedName)")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            throw HareruyaError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HareruyaError.networkError("Invalid response type")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HareruyaError.serverError(statusCode: httpResponse.statusCode)
        }

        let dto: HareruyaResponseDTO
        do {
            dto = try decoder.decode(HareruyaResponseDTO.self, from: data)
        } catch {
            throw HareruyaError.decodingError(error.localizedDescription)
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
