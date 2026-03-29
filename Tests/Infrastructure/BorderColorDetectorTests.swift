import Testing
import Foundation
import CoreGraphics
@testable import MTGCardScanner

@Suite("BorderColorDetector Tests")
struct BorderColorDetectorTests {

    let detector = BorderColorDetector()

    // MARK: - Border Detection

    @Test("Detects black border from a predominantly dark-edged image")
    func detectsBlackBorder() {
        let image = makeTestImage(
            width: 100, height: 140,
            borderColor: (r: 0, g: 0, b: 0),
            innerColor: (r: 180, g: 140, b: 100)
        )
        let result = detector.detectBorderColor(in: image)
        #expect(result == .black)
    }

    @Test("Detects white border from a predominantly light-edged image")
    func detectsWhiteBorder() {
        let image = makeTestImage(
            width: 100, height: 140,
            borderColor: (r: 255, g: 255, b: 255),
            innerColor: (r: 80, g: 60, b: 40)
        )
        let result = detector.detectBorderColor(in: image)
        #expect(result == .white)
    }

    @Test("Returns nil for a very small image")
    func returnsNilForSmallImage() {
        let image = makeTestImage(
            width: 3, height: 3,
            borderColor: (r: 0, g: 0, b: 0),
            innerColor: (r: 0, g: 0, b: 0)
        )
        let result = detector.detectBorderColor(in: image)
        #expect(result == nil)
    }

    @Test("BorderColor enum has expected cases (black, white, borderless)")
    func borderColorHasExpectedCases() {
        let black = BorderColor.black
        let white = BorderColor.white
        let borderless = BorderColor.borderless

        #expect(black.rawValue == "black")
        #expect(white.rawValue == "white")
        #expect(borderless.rawValue == "borderless")
    }

    @Test("BorderColor is Sendable")
    func borderColorIsSendable() {
        let color: any Sendable = BorderColor.black
        #expect(color is BorderColor)
    }

    // MARK: - Helpers

    /// Creates a test CGImage with a solid border color and a different inner fill.
    private func makeTestImage(
        width: Int,
        height: Int,
        borderColor: (r: UInt8, g: UInt8, b: UInt8),
        innerColor: (r: UInt8, g: UInt8, b: UInt8),
        borderWidth: Int = 5
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!

        // Fill entire image with border color
        context.setFillColor(red: CGFloat(borderColor.r) / 255.0,
                             green: CGFloat(borderColor.g) / 255.0,
                             blue: CGFloat(borderColor.b) / 255.0,
                             alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Fill inner area with inner color
        context.setFillColor(red: CGFloat(innerColor.r) / 255.0,
                             green: CGFloat(innerColor.g) / 255.0,
                             blue: CGFloat(innerColor.b) / 255.0,
                             alpha: 1.0)
        context.fill(CGRect(
            x: borderWidth,
            y: borderWidth,
            width: width - borderWidth * 2,
            height: height - borderWidth * 2
        ))

        return context.makeImage()!
    }
}
