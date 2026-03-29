import Foundation
import CoreGraphics

// MARK: - Border Color

/// Represents the border color of an MTG card.
enum BorderColor: String, Sendable, Equatable {
    case black
    case white
    case borderless
}

// MARK: - Border Color Detector

/// Detects the border color of an MTG card by sampling pixels along the edges of the image
/// and computing average luminance.
struct BorderColorDetector: Sendable {

    /// Minimum image dimension required for reliable detection.
    private let minimumDimension = 10

    /// Number of sample points per edge.
    private let samplesPerEdge = 10

    /// Luminance threshold above which a border is considered white.
    private let whiteThreshold: Double = 0.7

    /// Luminance threshold below which a border is considered black.
    private let blackThreshold: Double = 0.3

    /// Detects the border color of a card image by sampling edge pixels.
    ///
    /// Returns `nil` if the image is too small to analyze reliably.
    func detectBorderColor(in image: CGImage) -> BorderColor? {
        let width = image.width
        let height = image.height

        guard width >= minimumDimension, height >= minimumDimension else {
            return nil
        }

        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let pointer = CFDataGetBytePtr(data) else {
            return nil
        }

        let bytesPerRow = image.bytesPerRow
        let bitsPerPixel = image.bitsPerPixel
        let bytesPerPixel = bitsPerPixel / 8

        guard bytesPerPixel >= 3 else { return nil }

        // Determine component order: BGRA vs RGBA
        let bitmapInfo = image.bitmapInfo
        let byteOrder = CGBitmapInfo(rawValue: bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue)

        // Determine if pixel format is BGR (byte order 32 little with alpha first/last)
        let isBGR = byteOrder == .byteOrder32Little

        // Sample edge pixels
        var totalLuminance: Double = 0
        var sampleCount = 0

        let samplePoints = generateEdgeSamplePoints(width: width, height: height)

        for point in samplePoints {
            let offset = point.y * bytesPerRow + point.x * bytesPerPixel

            let r: Double
            let g: Double
            let b: Double

            if isBGR {
                // BGRA layout
                b = Double(pointer[offset]) / 255.0
                g = Double(pointer[offset + 1]) / 255.0
                r = Double(pointer[offset + 2]) / 255.0
            } else {
                // RGBA layout
                r = Double(pointer[offset]) / 255.0
                g = Double(pointer[offset + 1]) / 255.0
                b = Double(pointer[offset + 2]) / 255.0
            }

            // ITU-R BT.601 luminance formula
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            totalLuminance += luminance
            sampleCount += 1
        }

        guard sampleCount > 0 else { return nil }

        let averageLuminance = totalLuminance / Double(sampleCount)

        if averageLuminance > whiteThreshold {
            return .white
        } else if averageLuminance < blackThreshold {
            return .black
        } else {
            return .borderless
        }
    }

    // MARK: - Private

    /// Generates sample points distributed along the four edges of the image.
    private func generateEdgeSamplePoints(width: Int, height: Int) -> [(x: Int, y: Int)] {
        var points: [(x: Int, y: Int)] = []

        // Left edge: x=2, distributed vertically
        for i in 0..<samplesPerEdge {
            let y = (height * (i + 1)) / (samplesPerEdge + 1)
            points.append((x: 2, y: y))
        }

        // Right edge: x=width-3, distributed vertically
        for i in 0..<samplesPerEdge {
            let y = (height * (i + 1)) / (samplesPerEdge + 1)
            points.append((x: width - 3, y: y))
        }

        // Top edge: y=2, distributed horizontally
        for i in 0..<samplesPerEdge {
            let x = (width * (i + 1)) / (samplesPerEdge + 1)
            points.append((x: x, y: 2))
        }

        // Bottom edge: y=height-3, distributed horizontally
        for i in 0..<samplesPerEdge {
            let x = (width * (i + 1)) / (samplesPerEdge + 1)
            points.append((x: x, y: height - 3))
        }

        return points
    }
}
