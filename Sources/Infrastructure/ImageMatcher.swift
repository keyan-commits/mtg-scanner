import Foundation
import CoreGraphics
import Vision

// MARK: - Image Matcher

/// Compares card images using Apple's VNFeaturePrint for visual similarity.
///
/// Used as a tiebreaker when metadata filtering (name, artist, year, border)
/// leaves multiple candidate printings. Downloads reference images in memory,
/// generates feature prints, and picks the closest match.
struct ImageMatcher: Sendable {

    /// Generates a VNFeaturePrintObservation for the given image.
    func generateFeaturePrint(for image: CGImage) async -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    /// Computes the distance between two images using feature prints.
    /// Lower distance = more similar. Returns nil if either image fails.
    func distance(between image1: CGImage, and image2: CGImage) async -> Float? {
        guard let fp1 = await generateFeaturePrint(for: image1),
              let fp2 = await generateFeaturePrint(for: image2) else {
            return nil
        }

        var distance: Float = 0
        do {
            try fp1.computeDistance(&distance, to: fp2)
            return distance
        } catch {
            return nil
        }
    }

    /// Finds the best matching image from a list of candidates.
    ///
    /// - Parameters:
    ///   - source: The user's card photo.
    ///   - candidates: Reference card images to compare against.
    /// - Returns: The index of the closest matching candidate, or nil.
    func findBestMatch(for source: CGImage, among candidates: [CGImage]) async -> Int? {
        guard !candidates.isEmpty else { return nil }

        guard let sourcePrint = await generateFeaturePrint(for: source) else {
            return nil
        }

        var bestIndex: Int?
        var bestDistance: Float = .greatestFiniteMagnitude

        for (index, candidate) in candidates.enumerated() {
            guard let candidatePrint = await generateFeaturePrint(for: candidate) else {
                continue
            }

            var dist: Float = 0
            do {
                try sourcePrint.computeDistance(&dist, to: candidatePrint)
                // 5% tolerance: only replace if significantly better.
                // This preserves priority ordering when distances are close.
                let threshold = bestDistance * 0.95
                if dist < threshold || bestIndex == nil {
                    bestDistance = dist
                    bestIndex = index
                }
            } catch {
                continue
            }
        }

        return bestIndex
    }

    /// Downloads an image from a URL into memory and converts to CGImage.
    /// No disk storage — data is released when the function returns.
    func downloadImage(from urlString: String) async -> CGImage? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Convert Data → CGImage via CGImageSource (memory only, no disk)
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }

            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        } catch {
            return nil
        }
    }
}
