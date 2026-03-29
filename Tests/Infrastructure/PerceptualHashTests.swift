import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

@Suite("PerceptualHash Tests")
struct PerceptualHashTests {

    // MARK: - Hash Computation

    @Test("Computes a hash from a valid image (not nil)")
    func computeHashFromValidImage() {
        let image = makeTestImage(width: 100, height: 100, red: 0.5, green: 0.3, blue: 0.8)
        let hash = PerceptualHash.compute(from: image)
        #expect(hash != nil)
    }

    @Test("Same image produces same hash")
    func sameImageProducesSameHash() {
        let image = makeTestImage(width: 200, height: 200, red: 0.4, green: 0.6, blue: 0.2)
        let hash1 = PerceptualHash.compute(from: image)
        let hash2 = PerceptualHash.compute(from: image)
        #expect(hash1 != nil)
        #expect(hash1 == hash2)
    }

    @Test("Different images produce different hashes")
    func differentImagesProduceDifferentHashes() {
        let imageA = makeTestImage(width: 200, height: 200, red: 1.0, green: 0.0, blue: 0.0)
        let imageB = makeTestImage(width: 200, height: 200, red: 0.0, green: 0.0, blue: 1.0)
        let hashA = PerceptualHash.compute(from: imageA)
        let hashB = PerceptualHash.compute(from: imageB)
        #expect(hashA != nil)
        #expect(hashB != nil)
        #expect(hashA != hashB)
    }

    // MARK: - Hamming Distance

    @Test("Hamming distance of identical hashes is 0")
    func hammingDistanceIdentical() {
        let distance = PerceptualHash.hammingDistance(0xDEADBEEF, 0xDEADBEEF)
        #expect(distance == 0)
    }

    @Test("Hamming distance of completely different hashes is greater than 0")
    func hammingDistanceDifferent() {
        let distance = PerceptualHash.hammingDistance(0x0000000000000000, 0xFFFFFFFFFFFFFFFF)
        #expect(distance == 64)
    }

    @Test("Hamming distance of hashes differing by one bit is 1")
    func hammingDistanceOneBit() {
        let a: UInt64 = 0b1000
        let b: UInt64 = 0b0000
        #expect(PerceptualHash.hammingDistance(a, b) == 1)
    }

    @Test("Similar images have low Hamming distance")
    func similarImagesLowDistance() {
        // Two images with slightly different colors should produce similar hashes
        let imageA = makeTestImage(width: 200, height: 200, red: 0.5, green: 0.3, blue: 0.8)
        let imageB = makeTestImage(width: 200, height: 200, red: 0.52, green: 0.28, blue: 0.82)
        guard let hashA = PerceptualHash.compute(from: imageA),
              let hashB = PerceptualHash.compute(from: imageB) else {
            Issue.record("Failed to compute hashes")
            return
        }
        let distance = PerceptualHash.hammingDistance(hashA, hashB)
        // Similar images should have distance well below 32 (half of 64)
        #expect(distance < 20)
    }

    // MARK: - Sendable Conformance

    @Test("PerceptualHash is Sendable")
    func isSendable() {
        let ph: any Sendable = PerceptualHash()
        #expect(ph is PerceptualHash)
    }

    // MARK: - Edge Cases

    @Test("Hash works with very small image")
    func hashWorksWithSmallImage() {
        let image = makeTestImage(width: 8, height: 8, red: 0.5, green: 0.5, blue: 0.5)
        let hash = PerceptualHash.compute(from: image)
        #expect(hash != nil)
    }

    @Test("Hash works with non-square image")
    func hashWorksWithNonSquareImage() {
        let image = makeTestImage(width: 300, height: 100, red: 0.3, green: 0.7, blue: 0.1)
        let hash = PerceptualHash.compute(from: image)
        #expect(hash != nil)
    }

    // MARK: - Helpers

    /// Creates a test CGImage filled with a gradient and colored rectangles.
    private func makeTestImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // Fill with gradient based on provided color
        for y in 0..<height {
            let factor = CGFloat(y) / CGFloat(height)
            context.setFillColor(
                red: red * factor,
                green: green * (1.0 - factor),
                blue: blue,
                alpha: 1.0
            )
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }

        // Draw colored rectangles for visual complexity
        context.setFillColor(red: 1.0 - red, green: green, blue: 1.0 - blue, alpha: 1.0)
        context.fill(CGRect(x: width / 10, y: height / 10, width: width / 3, height: height / 4))
        context.setFillColor(red: red, green: 1.0 - green, blue: blue, alpha: 1.0)
        context.fill(CGRect(x: width / 4, y: height / 2, width: width / 3, height: height / 5))

        return context.makeImage()!
    }
}
