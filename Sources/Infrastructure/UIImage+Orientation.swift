import UIKit

extension UIImage {
    /// Returns a copy whose pixel data has the EXIF orientation baked in
    /// (so `imageOrientation == .up`).
    ///
    /// Why: iPhone photos store rotation as metadata. Calling `.cgImage` returns the
    /// raw pixel buffer without applying that metadata, so a portrait photo extracted
    /// via `UIImage(data:).cgImage` ends up sideways. Use this before extracting the
    /// CGImage for downstream processing — display, ML inference, or sending to Gemini.
    func orientationNormalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
