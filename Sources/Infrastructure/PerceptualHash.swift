import Foundation
import CoreGraphics
import Accelerate

/// Computes a 64-bit perceptual hash (pHash) for an image.
/// The hash is invariant to scale and minor color/brightness changes.
struct PerceptualHash: Sendable {

    /// Computes the pHash of a CGImage.
    /// Algorithm: resize to 32x32 grayscale -> DCT -> top-left 8x8 -> median threshold -> 64-bit hash
    static func compute(from image: CGImage) -> UInt64? {
        // Step 1: Resize to 32x32 grayscale
        guard let grayscale = resizeToGrayscale(image, size: 32) else { return nil }

        // Step 2: Apply DCT (Discrete Cosine Transform)
        let dctResult = applyDCT(grayscale, size: 32)

        // Step 3: Extract top-left 8x8 (low frequencies, excluding DC component)
        var lowFreq: [Float] = []
        for y in 0..<8 {
            for x in 0..<8 {
                if x == 0 && y == 0 { continue } // skip DC
                lowFreq.append(dctResult[y * 32 + x])
            }
        }

        // Step 4: Compute median
        let sorted = lowFreq.sorted()
        let median = sorted[sorted.count / 2]

        // Step 5: Generate hash: each bit = 1 if value > median
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

    /// Computes the Hamming distance between two hashes.
    /// Lower = more similar. 0 = identical. Max = 63.
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount
    }

    // MARK: - Private Helpers

    /// Resizes a CGImage to NxN grayscale pixel array.
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

    /// Applies a simple row+column DCT.
    private static func applyDCT(_ pixels: [Float], size: Int) -> [Float] {
        var result = [Float](repeating: 0, count: size * size)

        // Row-wise DCT
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

        // Column-wise DCT
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
