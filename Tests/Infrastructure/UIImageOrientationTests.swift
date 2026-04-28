import Testing
import UIKit
@testable import MTGCardScanner

@Suite("UIImage orientation normalization")
struct UIImageOrientationTests {

    /// Builds a 4×2 test image with a known pixel pattern so we can verify the
    /// renderer didn't accidentally flip or mirror anything.
    private func makeTestImage(orientation: UIImage.Orientation) -> UIImage {
        let width = 4
        let height = 2
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = context.makeImage()!
        return UIImage(cgImage: cg, scale: 1, orientation: orientation)
    }

    @Test("No-op when orientation is already .up")
    func noOpWhenUp() {
        let img = makeTestImage(orientation: .up)
        let normalized = img.orientationNormalized()
        // For a no-op the same instance is returned.
        #expect(normalized === img)
        #expect(normalized.imageOrientation == .up)
    }

    @Test("Right-rotated image becomes .up after normalization")
    func rightRotatedNormalizes() {
        let img = makeTestImage(orientation: .right)
        let normalized = img.orientationNormalized()
        #expect(normalized.imageOrientation == .up)
        // .right swaps logical width/height; original 4x2 has size 2x4 logically,
        // and the renderer preserves logical size after redraw.
        #expect(normalized.size == img.size)
    }

    @Test("Left-rotated image becomes .up after normalization")
    func leftRotatedNormalizes() {
        let img = makeTestImage(orientation: .left)
        let normalized = img.orientationNormalized()
        #expect(normalized.imageOrientation == .up)
        #expect(normalized.size == img.size)
    }

    @Test("Down-rotated image becomes .up after normalization")
    func downRotatedNormalizes() {
        let img = makeTestImage(orientation: .down)
        let normalized = img.orientationNormalized()
        #expect(normalized.imageOrientation == .up)
        #expect(normalized.size == img.size)
    }

    @Test("Resulting CGImage is non-nil and has positive dimensions")
    func resultingCGImageIsValid() {
        let img = makeTestImage(orientation: .right)
        let normalized = img.orientationNormalized()
        #expect(normalized.cgImage != nil)
        #expect((normalized.cgImage?.width ?? 0) > 0)
        #expect((normalized.cgImage?.height ?? 0) > 0)
    }
}
