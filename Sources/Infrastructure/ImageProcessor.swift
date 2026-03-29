import Foundation
import ImageIO
import CoreGraphics

// MARK: - Image Processor

/// Memory-efficient image processing using ImageIO for downsampling card photos.
///
/// Uses `CGImageSource` thumbnail generation instead of loading the full image
/// into memory, which is critical when processing batches of high-resolution
/// photos from the user's library.
struct ImageProcessor: Sendable {

    /// Downsamples image data to fit within the given maximum dimension.
    ///
    /// Uses `CGImageSourceCreateThumbnailAtIndex` for memory-efficient
    /// downsampling. Images smaller than `maxDimension` are returned at
    /// their original size (never upscaled). EXIF orientation is applied
    /// via `kCGImageSourceCreateThumbnailWithTransform`.
    ///
    /// - Parameters:
    ///   - data: Raw image data (JPEG, PNG, HEIC, etc.).
    ///   - maxDimension: The maximum width or height in points. Defaults to 1500.
    /// - Returns: A downsampled `CGImage`, or `nil` if the data is invalid.
    func downsample(data: Data, maxDimension: CGFloat = 1500) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            sourceOptions as CFDictionary
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Converts raw image data to a `CGImage` without downsampling.
    ///
    /// - Parameter data: Raw image data (JPEG, PNG, HEIC, etc.).
    /// - Returns: A `CGImage`, or `nil` if the data is invalid.
    func cgImage(from data: Data) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            sourceOptions as CFDictionary
        ) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
