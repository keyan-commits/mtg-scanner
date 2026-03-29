import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import MTGCardScanner

// MARK: - Tests

@Suite("ImageProcessor Tests")
struct ImageProcessorTests {

    private let processor = ImageProcessor()

    // MARK: - Helpers

    /// Creates a minimal CGImage of the given size and returns its PNG data.
    private static func makePNGData(width: Int, height: Int) -> Data? {
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

        // Fill with a solid color so the image is valid
        context.setFillColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else { return nil }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    // MARK: - Downsample Tests

    @Test("Downsampling preserves image and does not return nil")
    func downsamplePreservesImage() {
        let data = ImageProcessorTests.makePNGData(width: 3000, height: 2000)!
        let result = processor.downsample(data: data, maxDimension: 1500)

        #expect(result != nil)

        // The downsampled image should have a max dimension of 1500
        if let image = result {
            let maxDim = max(image.width, image.height)
            #expect(maxDim <= 1500)
        }
    }

    @Test("Images already smaller than max dimension are not upscaled")
    func smallImageNotUpscaled() {
        let data = ImageProcessorTests.makePNGData(width: 500, height: 300)!
        let result = processor.downsample(data: data, maxDimension: 1500)

        #expect(result != nil)

        if let image = result {
            // Should remain at original size, not upscaled to 1500
            #expect(image.width <= 500)
            #expect(image.height <= 300)
        }
    }

    @Test("Returns nil for invalid data")
    func returnsNilForInvalidData() {
        let invalidData = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        let result = processor.downsample(data: invalidData, maxDimension: 1500)

        #expect(result == nil)
    }

    // MARK: - cgImage Tests

    @Test("cgImage converts valid PNG data to CGImage")
    func cgImageFromValidData() {
        let data = ImageProcessorTests.makePNGData(width: 100, height: 100)!
        let result = processor.cgImage(from: data)

        #expect(result != nil)
        #expect(result?.width == 100)
        #expect(result?.height == 100)
    }

    @Test("cgImage returns nil for invalid data")
    func cgImageReturnsNilForInvalidData() {
        let invalidData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let result = processor.cgImage(from: invalidData)

        #expect(result == nil)
    }
}
