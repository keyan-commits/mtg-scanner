#!/usr/bin/env swift
// =============================================================================
// generate_visual_index.swift
//
// Generates a visual_index.json file containing perceptual hashes (pHash) for
// all unique MTG card illustrations from Scryfall's bulk data.
//
// Usage:
//   swift Scripts/generate_visual_index.swift
//
// Output:
//   Resources/visual_index.json
//
// The script:
//   1. Downloads Scryfall's oracle_cards bulk data catalog
//   2. For each unique illustration, downloads the art_crop image
//   3. Computes the perceptual hash
//   4. Saves progress periodically (resume on interruption)
//   5. Outputs JSON array of {illustrationID, cardName, hash}
//
// Respects Scryfall rate limits (100ms between requests).
// Estimated runtime: ~2-4 hours for ~27K unique illustrations.
// =============================================================================

import Foundation
import CoreGraphics
import ImageIO

// MARK: - Perceptual Hash (standalone copy for script use)

enum PHash {
    static func compute(from image: CGImage) -> UInt64? {
        guard let grayscale = resizeToGrayscale(image, size: 32) else { return nil }
        let dctResult = applyDCT(grayscale, size: 32)

        var lowFreq: [Float] = []
        for y in 0..<8 {
            for x in 0..<8 {
                if x == 0 && y == 0 { continue }
                lowFreq.append(dctResult[y * 32 + x])
            }
        }

        let sorted = lowFreq.sorted()
        let median = sorted[sorted.count / 2]

        var hash: UInt64 = 0
        var bit: UInt64 = 1
        for y in 0..<8 {
            for x in 0..<8 {
                if x == 0 && y == 0 { continue }
                if dctResult[y * 32 + x] > median {
                    hash |= bit
                }
                bit <<= 1
            }
        }

        return hash
    }

    private static func resizeToGrayscale(_ image: CGImage, size: Int) -> [Float]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: size * size)
        return (0..<(size * size)).map { Float(bytes[$0]) }
    }

    private static func applyDCT(_ pixels: [Float], size: Int) -> [Float] {
        var result = [Float](repeating: 0, count: size * size)

        var rowTransformed = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for u in 0..<size {
                var sum: Float = 0
                for x in 0..<size {
                    sum += pixels[y * size + x] * cos(Float.pi * Float(2 * x + 1) * Float(u) / Float(2 * size))
                }
                rowTransformed[y * size + u] = sum
            }
        }

        for u in 0..<size {
            for v in 0..<size {
                var sum: Float = 0
                for y in 0..<size {
                    sum += rowTransformed[y * size + u] * cos(Float.pi * Float(2 * y + 1) * Float(v) / Float(2 * size))
                }
                result[v * size + u] = sum
            }
        }

        return result
    }
}

// MARK: - Data Models

struct BulkDataCatalog: Codable {
    let data: [BulkDataEntry]
}

struct BulkDataEntry: Codable {
    let type: String
    let downloadUri: String

    enum CodingKeys: String, CodingKey {
        case type
        case downloadUri = "download_uri"
    }
}

struct ScryfallCard: Codable {
    let name: String
    let illustrationId: String?
    let imageUris: ImageURIs?

    enum CodingKeys: String, CodingKey {
        case name
        case illustrationId = "illustration_id"
        case imageUris = "image_uris"
    }
}

struct ImageURIs: Codable {
    let artCrop: String?

    enum CodingKeys: String, CodingKey {
        case artCrop = "art_crop"
    }
}

struct IndexEntry: Codable {
    let illustrationID: String
    let cardName: String
    let hash: UInt64
}

// MARK: - Progress Tracking

let progressFilePath = "Resources/visual_index_progress.json"
let outputFilePath = "Resources/visual_index.json"

func loadProgress() -> [String: IndexEntry] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: progressFilePath)),
          let entries = try? JSONDecoder().decode([IndexEntry].self, from: data) else {
        return [:]
    }
    var dict: [String: IndexEntry] = [:]
    for entry in entries {
        dict[entry.illustrationID] = entry
    }
    print("Loaded \(dict.count) previously computed hashes.")
    return dict
}

func saveProgress(_ entries: [String: IndexEntry]) {
    let sorted = entries.values.sorted { $0.cardName < $1.cardName }
    guard let data = try? JSONEncoder().encode(sorted) else { return }
    try? data.write(to: URL(fileURLWithPath: progressFilePath))
}

func saveFinalOutput(_ entries: [String: IndexEntry]) {
    let sorted = entries.values.sorted { $0.cardName < $1.cardName }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(sorted) else {
        print("ERROR: Failed to encode final output.")
        return
    }
    do {
        try data.write(to: URL(fileURLWithPath: outputFilePath))
        print("Saved \(sorted.count) entries to \(outputFilePath)")
    } catch {
        print("ERROR: Failed to write output: \(error)")
    }
}

// MARK: - Network Helpers

func downloadJSON<T: Codable>(from urlString: String) -> T? {
    guard let url = URL(string: urlString) else { return nil }
    let semaphore = DispatchSemaphore(value: 0)
    var result: T?

    let task = URLSession.shared.dataTask(with: url) { data, _, error in
        defer { semaphore.signal() }
        guard let data = data, error == nil else { return }
        result = try? JSONDecoder().decode(T.self, from: data)
    }
    task.resume()
    semaphore.wait()
    return result
}

func downloadData(from urlString: String) -> Data? {
    guard let url = URL(string: urlString) else { return nil }
    let semaphore = DispatchSemaphore(value: 0)
    var result: Data?

    let task = URLSession.shared.dataTask(with: url) { data, _, error in
        defer { semaphore.signal() }
        guard let data = data, error == nil else { return }
        result = data
    }
    task.resume()
    semaphore.wait()
    return result
}

func cgImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: - Main

func main() {
    // Ensure output directory exists
    try? FileManager.default.createDirectory(
        atPath: "Resources",
        withIntermediateDirectories: true
    )

    print("Fetching Scryfall bulk data catalog...")
    guard let catalog: BulkDataCatalog = downloadJSON(from: "https://api.scryfall.com/bulk-data") else {
        print("ERROR: Failed to fetch bulk data catalog.")
        exit(1)
    }

    guard let oracleEntry = catalog.data.first(where: { $0.type == "oracle_cards" }) else {
        print("ERROR: No oracle_cards entry found in bulk data catalog.")
        exit(1)
    }

    print("Downloading oracle cards from: \(oracleEntry.downloadUri)")
    guard let cardsData = downloadData(from: oracleEntry.downloadUri) else {
        print("ERROR: Failed to download oracle cards.")
        exit(1)
    }

    guard let cards = try? JSONDecoder().decode([ScryfallCard].self, from: cardsData) else {
        print("ERROR: Failed to parse oracle cards JSON.")
        exit(1)
    }

    print("Loaded \(cards.count) cards from Scryfall.")

    // Deduplicate by illustration_id
    var uniqueCards: [String: ScryfallCard] = [:]
    for card in cards {
        guard let illustrationId = card.illustrationId,
              card.imageUris?.artCrop != nil else { continue }
        if uniqueCards[illustrationId] == nil {
            uniqueCards[illustrationId] = card
        }
    }

    print("Found \(uniqueCards.count) unique illustrations with art_crop URLs.")

    // Load existing progress
    var completedEntries = loadProgress()
    let totalToProcess = uniqueCards.count
    var processedCount = completedEntries.count
    let saveInterval = 100 // Save progress every N cards
    var sinceLastSave = 0

    print("Starting hash computation (\(totalToProcess - processedCount) remaining)...")
    let startTime = Date()

    for (illustrationId, card) in uniqueCards {
        // Skip already processed
        if completedEntries[illustrationId] != nil { continue }

        // Rate limit: 100ms between Scryfall requests
        Thread.sleep(forTimeInterval: 0.1)

        guard let artCropURL = card.imageUris?.artCrop,
              let imageData = downloadData(from: artCropURL),
              let image = cgImage(from: imageData),
              let hash = PHash.compute(from: image) else {
            processedCount += 1
            if processedCount % 100 == 0 {
                print("  [\(processedCount)/\(totalToProcess)] Skipped \(card.name) (download or hash failed)")
            }
            continue
        }

        let entry = IndexEntry(
            illustrationID: illustrationId,
            cardName: card.name,
            hash: hash
        )
        completedEntries[illustrationId] = entry
        processedCount += 1
        sinceLastSave += 1

        if processedCount % 100 == 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            let rate = Double(processedCount) / elapsed
            let remaining = Double(totalToProcess - processedCount) / rate
            let remainingMinutes = Int(remaining / 60)
            print("  [\(processedCount)/\(totalToProcess)] \(card.name) - ~\(remainingMinutes) min remaining")
        }

        // Periodic save
        if sinceLastSave >= saveInterval {
            saveProgress(completedEntries)
            sinceLastSave = 0
        }
    }

    // Final save
    saveFinalOutput(completedEntries)

    // Clean up progress file
    try? FileManager.default.removeItem(atPath: progressFilePath)

    let totalTime = Date().timeIntervalSince(startTime)
    let minutes = Int(totalTime / 60)
    let seconds = Int(totalTime.truncatingRemainder(dividingBy: 60))
    print("Done! Processed \(completedEntries.count) illustrations in \(minutes)m \(seconds)s.")
}

main()
