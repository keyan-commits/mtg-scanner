#!/usr/bin/env swift
// =============================================================================
// generate_embeddings.swift
//
// Generates VNFeaturePrint embeddings for MTG cards from Scryfall images.
// Output is a JSON array matching VisualEmbeddingStore.Embedding format,
// suitable for bundling in the app as base_embeddings.json.
//
// Usage:
//   swift scripts/generate_embeddings.swift [--limit N]
//
// Output:
//   Resources/base_embeddings.json
//
// The script:
//   1. Downloads Scryfall's oracle_cards bulk data catalog
//   2. For each card (up to --limit), downloads the normal image
//   3. Computes VNFeaturePrint and serializes via NSKeyedArchiver
//   4. Saves progress to a checkpoint file (resume on interruption)
//   5. Outputs JSON array of Embedding structs
//
// Respects Scryfall rate limits (100ms between requests).
// =============================================================================

import Foundation
import Vision
import AppKit

// MARK: - CLI Arguments

func parseLimit() -> Int {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--limit"), idx + 1 < args.count,
       let limit = Int(args[idx + 1]) {
        return limit
    }
    return 5000
}

let cardLimit = parseLimit()
print("Card limit: \(cardLimit)")

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
    let setCode: String
    let collectorNumber: String
    let imageUris: ImageURIs?
    let layout: String?

    enum CodingKeys: String, CodingKey {
        case name
        case setCode = "set"
        case collectorNumber = "collector_number"
        case imageUris = "image_uris"
        case layout
    }
}

struct ImageURIs: Codable {
    let normal: String?

    enum CodingKeys: String, CodingKey {
        case normal
    }
}

/// Matches VisualEmbeddingStore.Embedding exactly
struct EmbeddingEntry: Codable {
    let cardName: String
    let setCode: String
    let collectorNumber: String
    let featurePrintData: Data  // NSKeyedArchiver-encoded, base64 in JSON
    let addedAt: Date
    let isCorrection: Bool
}

// MARK: - Progress Tracking

let progressFilePath = "Resources/base_embeddings_progress.json"
let outputFilePath = "Resources/base_embeddings.json"

func loadProgress() -> [String: EmbeddingEntry] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: progressFilePath)),
          let entries = try? JSONDecoder().decode([EmbeddingEntry].self, from: data) else {
        return [:]
    }
    var dict: [String: EmbeddingEntry] = [:]
    for entry in entries {
        let key = "\(entry.setCode)/\(entry.collectorNumber)"
        dict[key] = entry
    }
    print("Loaded \(dict.count) previously computed embeddings from checkpoint.")
    return dict
}

func saveProgress(_ entries: [String: EmbeddingEntry]) {
    let sorted = entries.values.sorted { $0.cardName < $1.cardName }
    guard let data = try? JSONEncoder().encode(sorted) else { return }
    try? data.write(to: URL(fileURLWithPath: progressFilePath))
}

func saveFinalOutput(_ entries: [String: EmbeddingEntry]) {
    let sorted = entries.values.sorted { $0.cardName < $1.cardName }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
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

// MARK: - Vision Helpers

func generateFeaturePrint(from imageData: Data) -> VNFeaturePrintObservation? {
    guard let nsImage = NSImage(data: imageData),
          let tiffData = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let cgImage = bitmap.cgImage else { return nil }

    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
        return request.results?.first
    } catch {
        return nil
    }
}

func serializeFeaturePrint(_ observation: VNFeaturePrintObservation) -> Data? {
    try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
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

    // Filter to cards that have normal images and are not tokens/art_series etc.
    let validLayouts = Set(["normal", "split", "flip", "transform", "modal_dfc", "meld", "leveler", "class", "saga", "adventure", "mutate", "prototype", "battle", "case"])
    let eligibleCards = cards.filter { card in
        guard card.imageUris?.normal != nil else { return false }
        if let layout = card.layout {
            return validLayouts.contains(layout)
        }
        return true
    }

    print("Found \(eligibleCards.count) eligible cards with normal image URLs.")

    // Take up to limit
    let cardsToProcess = Array(eligibleCards.prefix(cardLimit))
    print("Will process \(cardsToProcess.count) cards (limit: \(cardLimit)).")

    // Load existing progress
    var completedEntries = loadProgress()
    let totalToProcess = cardsToProcess.count
    var processedCount = 0
    var newCount = 0
    let saveInterval = 100
    var sinceLastSave = 0

    let fixedDate = ISO8601DateFormatter().date(from: "2026-04-15T00:00:00Z") ?? Date()

    print("Starting embedding computation (\(totalToProcess - completedEntries.count) remaining)...")
    let startTime = Date()

    for card in cardsToProcess {
        let key = "\(card.setCode)/\(card.collectorNumber)"
        processedCount += 1

        // Skip already processed
        if completedEntries[key] != nil {
            if processedCount % 500 == 0 {
                print("  [\(processedCount)/\(totalToProcess)] Skipping \(card.name) (already in checkpoint)")
            }
            continue
        }

        // Rate limit: 100ms between Scryfall requests
        Thread.sleep(forTimeInterval: 0.1)

        guard let normalURL = card.imageUris?.normal,
              let imageData = downloadData(from: normalURL),
              let featurePrint = generateFeaturePrint(from: imageData),
              let serialized = serializeFeaturePrint(featurePrint) else {
            if processedCount % 100 == 0 {
                print("  [\(processedCount)/\(totalToProcess)] Skipped \(card.name) (download or featureprint failed)")
            }
            continue
        }

        let entry = EmbeddingEntry(
            cardName: card.name,
            setCode: card.setCode,
            collectorNumber: card.collectorNumber,
            featurePrintData: serialized,
            addedAt: fixedDate,
            isCorrection: false
        )
        completedEntries[key] = entry
        newCount += 1
        sinceLastSave += 1

        if processedCount % 100 == 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            let rate = Double(processedCount) / elapsed
            let remaining = Double(totalToProcess - processedCount) / rate
            let remainingMinutes = Int(remaining / 60)
            print("  [\(processedCount)/\(totalToProcess)] \(card.name) - ~\(remainingMinutes) min remaining (\(completedEntries.count) total)")
        }

        // Periodic save
        if sinceLastSave >= saveInterval {
            saveProgress(completedEntries)
            sinceLastSave = 0
            print("  Checkpoint saved (\(completedEntries.count) entries)")
        }
    }

    // Final save
    saveFinalOutput(completedEntries)

    // Clean up progress file
    try? FileManager.default.removeItem(atPath: progressFilePath)

    let totalTime = Date().timeIntervalSince(startTime)
    let minutes = Int(totalTime / 60)
    let seconds = Int(totalTime.truncatingRemainder(dividingBy: 60))
    print("Done! \(completedEntries.count) total embeddings (\(newCount) new) in \(minutes)m \(seconds)s.")
}

main()
