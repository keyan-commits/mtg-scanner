import Foundation

// MARK: - Bulk Data Info

struct BulkDataInfo: Sendable {
    let downloadURI: String
    let updatedAt: String
    let size: Int
}

// MARK: - Protocol

protocol BulkDataDownloaderProtocol: Sendable {
    func fetchBulkDataInfo() async throws -> BulkDataInfo
    func downloadBulkData() async throws -> URL
}

// MARK: - Errors

enum BulkDataError: Error, Sendable {
    case bulkDataNotFound
    case downloadFailed
    case invalidResponse
}

// MARK: - Scryfall Bulk Data Response DTOs

private struct ScryfallBulkDataListDTO: Codable {
    let data: [ScryfallBulkDataItemDTO]
}

private struct ScryfallBulkDataItemDTO: Codable {
    let type: String
    let downloadUri: String
    let updatedAt: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case type
        case downloadUri = "download_uri"
        case updatedAt = "updated_at"
        case size
    }
}

// MARK: - Implementation

final class ScryfallBulkDataDownloader: BulkDataDownloaderProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchBulkDataInfo() async throws -> BulkDataInfo {
        let url = URL(string: "https://api.scryfall.com/bulk-data")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BulkDataError.invalidResponse
        }

        let decoder = JSONDecoder()
        let bulkDataList = try decoder.decode(ScryfallBulkDataListDTO.self, from: data)

        guard let oracleCards = bulkDataList.data.first(where: { $0.type == "default_cards" }) else {
            throw BulkDataError.bulkDataNotFound
        }

        return BulkDataInfo(
            downloadURI: oracleCards.downloadUri,
            updatedAt: oracleCards.updatedAt,
            size: oracleCards.size
        )
    }

    func downloadBulkData() async throws -> URL {
        let info = try await fetchBulkDataInfo()

        guard let downloadURL = URL(string: info.downloadURI) else {
            throw BulkDataError.downloadFailed
        }

        let (tempFileURL, response) = try await session.download(from: downloadURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BulkDataError.downloadFailed
        }

        // Move to a known temp location so it persists until we process it
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scryfall_oracle_cards.json")

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: tempFileURL, to: destinationURL)

        return destinationURL
    }
}
