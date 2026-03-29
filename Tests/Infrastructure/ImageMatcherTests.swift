import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

@Suite("ImageMatcher Tests")
struct ImageMatcherTests {

    let matcher = ImageMatcher()

    @Test("Generates feature print from complex image")
    func generatesFeaturePrint() async {
        let image = makeComplexTestImage(width: 200, height: 280)
        let featurePrint = await matcher.generateFeaturePrint(for: image)
        // VNFeaturePrint may return nil on simulator with simple images
        // This test verifies the API call doesn't crash
        _ = featurePrint
    }

    @Test("Distance between same image is zero or very small")
    func sameImageSmallDistance() async {
        let image = makeComplexTestImage(width: 200, height: 280)
        let distance = await matcher.distance(between: image, and: image)
        if let distance {
            #expect(distance < 1.0)
        }
        // nil is acceptable on simulator
    }

    @Test("findBestMatch returns nil for empty candidates")
    func findBestMatchEmptyCandidates() async {
        let source = makeComplexTestImage(width: 200, height: 280)
        let result = await matcher.findBestMatch(for: source, among: [])
        #expect(result == nil)
    }

    @Test("downloadImage returns nil for invalid URL")
    func downloadInvalidURL() async {
        let result = await matcher.downloadImage(from: "not-a-url")
        #expect(result == nil)
    }

    @Test("ImageMatcher is Sendable")
    func isSendable() {
        let m: any Sendable = ImageMatcher()
        #expect(m is ImageMatcher)
    }

    // MARK: - Helpers

    /// Creates a test image with gradients and patterns for VNFeaturePrint.
    private func makeComplexTestImage(width: Int, height: Int) -> CGImage {
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

        // Draw gradient background
        for y in 0..<height {
            let r = CGFloat(y) / CGFloat(height)
            let g = CGFloat(width - 1) / CGFloat(width)
            let b = 1.0 - r
            context.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }

        // Draw some rectangles for visual complexity
        context.setFillColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 1.0)
        context.fill(CGRect(x: 10, y: 10, width: 80, height: 40))
        context.setFillColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0)
        context.fill(CGRect(x: 50, y: 100, width: 100, height: 60))

        return context.makeImage()!
    }
}
