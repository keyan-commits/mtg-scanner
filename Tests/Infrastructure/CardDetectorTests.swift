import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

// MARK: - Tests

@Suite("CardDetector Tests")
struct CardDetectorTests {

    private let detector = CardDetector()

    // MARK: - Helpers

    /// Creates a minimal CGImage filled with a solid color.
    private static func makeSolidImage(width: Int, height: Int,
                                       red: CGFloat = 0.5,
                                       green: CGFloat = 0.5,
                                       blue: CGFloat = 0.5) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(red: red, green: green, blue: blue, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }

    // MARK: - Detection Tests

    @Test("Returns nil for a tiny image that is too small for card detection")
    func detectAndCropReturnsNilForTinyImage() async {
        // A 5x5 image is far too small to contain a detectable card rectangle.
        let tinyImage = CardDetectorTests.makeSolidImage(width: 5, height: 5)!
        let result = await detector.detectAndCrop(from: tinyImage)

        #expect(result == nil)
    }

    @Test("Returns nil for a solid color image with no rectangle to detect")
    func detectAndCropReturnsNilForSolidColorImage() async {
        // A uniform solid color image has no edges or rectangles for Vision to detect.
        let solidImage = CardDetectorTests.makeSolidImage(width: 800, height: 600)!
        let result = await detector.detectAndCrop(from: solidImage)

        #expect(result == nil)
    }

    @Test("CardDetector conforms to Sendable")
    func cardDetectorIsSendable() {
        // Verify Sendable conformance by assigning to a Sendable-constrained binding.
        let sendable: any Sendable = detector
        #expect(sendable is CardDetector)
    }

    @Test("detectAndCrop API contract: calling with a valid image does not crash")
    func detectAndCropAPIContract() async {
        // Verify the API can be called without crashing, regardless of result.
        let image = CardDetectorTests.makeSolidImage(width: 400, height: 300)!
        let result = await detector.detectAndCrop(from: image)

        // Result may be nil (no card found) or a CGImage — both are valid outcomes.
        // The important thing is that the call completes without throwing or crashing.
        if let croppedImage = result {
            #expect(croppedImage.width > 0)
            #expect(croppedImage.height > 0)
        } else {
            #expect(result == nil)
        }
    }
}
