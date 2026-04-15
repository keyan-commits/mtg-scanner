#!/usr/bin/env swift

/// Trains an MTG Card Detector using Create ML Object Detection.
///
/// Prerequisites:
/// - macOS 14.0+ with Xcode installed
/// - Training data collected from the app (Documents/training_data/)
///
/// Usage:
///   1. Connect iPhone, open Finder, drag training_data/ folder to your Mac
///   2. Run: swift scripts/train_card_detector.swift /path/to/training_data
///   3. The trained model is automatically copied to the Xcode project
///
/// The script will:
///   - Read annotations.json from the training data directory
///   - Train an Object Detection model (transfer learning, ~250-500 iterations)
///   - Export as MTGCardDetector.mlmodel
///   - Copy to Resources/ in the project

import Foundation

#if canImport(CreateML)
import CreateML

// MARK: - Configuration

let modelName = "MTGCardDetector"
let maxIterations = 500

// MARK: - Parse Arguments

guard CommandLine.arguments.count > 1 else {
    print("""
    MTG Card Detector Trainer
    ========================

    Usage: swift train_card_detector.swift <training_data_path>

    The training_data path should contain:
      - annotations.json (Create ML Object Detection format)
      - photo_*.jpg files (source images)

    To collect training data:
      1. Open MTG Keyan → Scan → Split Cards
      2. Select a photo of cards
      3. Adjust bounding boxes to accurately cover each card
      4. Tap "Scan & Identify Cards" (this saves training data)
      5. Repeat with 50+ diverse photos

    Then sync the training_data folder from your iPhone to your Mac.
    """)
    exit(1)
}

let trainingDataPath = CommandLine.arguments[1]
let trainingDataURL = URL(fileURLWithPath: trainingDataPath)
let annotationsURL = trainingDataURL.appendingPathComponent("annotations.json")

// Verify training data exists
guard FileManager.default.fileExists(atPath: annotationsURL.path) else {
    print("ERROR: annotations.json not found at \(annotationsURL.path)")
    print("Make sure you've synced the training_data folder from your iPhone.")
    exit(1)
}

// Count images
guard let data = try? Data(contentsOf: annotationsURL),
      let annotations = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
    print("ERROR: Could not parse annotations.json")
    exit(1)
}

print("Found \(annotations.count) annotated images")

guard annotations.count >= 10 else {
    print("ERROR: Need at least 10 annotated images for training. You have \(annotations.count).")
    print("Collect more training data using the Split Cards tool.")
    exit(1)
}

// MARK: - Train

print("Training \(modelName) with \(annotations.count) images...")
print("Max iterations: \(maxIterations)")
print("This may take 5-15 minutes...\n")

do {
    let detector = try MLObjectDetector(
        trainingData: .directoryWithImagesAndJsonAnnotation(at: trainingDataURL),
        parameters: .init(
            maxIterations: maxIterations
        ),
        annotationType: .boundingBox()
    )

    // Get training metrics
    let trainingMetrics = detector.trainingMetrics
    let validationMetrics = detector.validationMetrics
    print("\nTraining complete!")
    print("Training metrics: \(trainingMetrics)")
    print("Validation metrics: \(validationMetrics)")

    // Save model
    let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
    let projectDir = scriptDir.deletingLastPathComponent()
    let resourcesDir = projectDir.appendingPathComponent("Resources")
    let modelURL = resourcesDir.appendingPathComponent("\(modelName).mlmodel")

    try detector.write(to: modelURL)
    print("\nModel saved to: \(modelURL.path)")
    print("\nNext steps:")
    print("  1. Open Xcode")
    print("  2. Drag \(modelName).mlmodel into the project (if not already added)")
    print("  3. Build and deploy to your iPhone")
    print("  4. The ML detector will automatically be used as Strategy 0")

} catch {
    print("ERROR: Training failed: \(error)")
    exit(1)
}

#else
print("ERROR: CreateML framework not available.")
print("This script must be run on macOS 14.0+ with Xcode installed.")
print("Run with: swift scripts/train_card_detector.swift /path/to/training_data")
exit(1)
#endif
