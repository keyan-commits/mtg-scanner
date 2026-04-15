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

    // MARK: - Art-Masked Frame Comparison

    /// Masks out the art region of a card image, leaving only the frame chrome
    /// (header, type line, set symbol, text box, border, collector info).
    ///
    /// Different printings of the same card share identical art but differ in
    /// frame, set symbol, border treatment, and collector info. By zeroing out
    /// the art, VNFeaturePrint focuses entirely on the distinguishing regions.
    ///
    /// Art region: approximately x: 7–93%, y: 8–52% (CGImage coords, origin top-left).
    func maskArtRegion(of image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw original card
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Fill art region with neutral gray (RGB 128,128,128)
        // Generous mask to ensure no art bleeds through
        let artX = Int(Double(w) * 0.07)
        let artY = Int(Double(h) * 0.08)
        let artW = Int(Double(w) * 0.86) // 0.93 - 0.07
        let artH = Int(Double(h) * 0.44) // 0.52 - 0.08
        ctx.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        ctx.fill(CGRect(x: artX, y: artY, width: artW, height: artH))

        return ctx.makeImage()
    }

    /// Finds the best matching printing by comparing frame chrome only.
    ///
    /// Masks the art region on both source and each candidate, then computes
    /// VNFeaturePrint distance on the masked images. Optionally combines with
    /// symbol-region distance for a weighted score.
    ///
    /// - Parameters:
    ///   - source: The user's card photo.
    ///   - candidates: Reference card images to compare against.
    ///   - symbolDistances: Optional per-candidate symbol distances (same indices).
    /// - Returns: The index of the best match, or nil.
    func findBestMatchByFrame(
        for source: CGImage,
        among candidates: [CGImage],
        symbolDistances: [Float?]? = nil
    ) async -> Int? {
        guard !candidates.isEmpty else { return nil }

        guard let maskedSource = maskArtRegion(of: source),
              let sourcePrint = await generateFeaturePrint(for: maskedSource) else {
            return nil
        }

        var bestIndex: Int?
        var bestScore: Float = .greatestFiniteMagnitude

        for (index, candidate) in candidates.enumerated() {
            guard let maskedCandidate = maskArtRegion(of: candidate),
                  let candidatePrint = await generateFeaturePrint(for: maskedCandidate) else {
                continue
            }

            var frameDist: Float = 0
            do {
                try sourcePrint.computeDistance(&frameDist, to: candidatePrint)
            } catch {
                continue
            }

            // Combine frame distance with symbol distance if available
            let score: Float
            if let symbolDists = symbolDistances, index < symbolDists.count,
               let symbolDist = symbolDists[index] {
                // 60% frame + 40% symbol (symbol is most discriminative single feature)
                score = 0.6 * frameDist + 0.4 * symbolDist
            } else {
                score = frameDist
            }

            let threshold = bestScore * 0.95
            if score < threshold || bestIndex == nil {
                bestScore = score
                bestIndex = index
            }
        }

        if let idx = bestIndex {
            print("[ImageMatcher] Frame comparison best: index \(idx), score \(bestScore)")
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
