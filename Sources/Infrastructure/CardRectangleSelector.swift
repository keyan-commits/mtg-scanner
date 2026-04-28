import CoreGraphics

/// Picks the most card-like rectangle from a set of detected rectangles.
///
/// Why this exists: `VNDetectRectanglesRequest` with `maximumObservations = 1`
/// gives us whichever rectangle has highest confidence. When the user puts a
/// card inside a scanner stand, the stand's interior walls form a high-contrast
/// rectangle against the wood/desk that often beats the card's own rectangle in
/// confidence — leaving the OCR pass running on the wrong region. We bump the
/// observation cap and pick the *card* deterministically.
///
/// Heuristic: among rectangles whose aspect ratio is in the card-like range,
/// pick the one with the **smallest area**. A card sitting inside a stand will
/// always be the smaller rectangle. Outside a stand there is only one
/// rectangle, so the rule degrades cleanly.
enum CardRectangleSelector {

    /// Magic cards are 2.5" × 3.5" → 0.714 width/height ratio. The acceptable
    /// range here is intentionally tighter than the request's own filter so we
    /// reject squarish containers (stand walls, photo frames).
    static let minAspectRatio: CGFloat = 0.65
    static let maxAspectRatio: CGFloat = 0.80

    /// Returns the bounding box of the most card-like rectangle, or nil if no
    /// rectangle in the input meets the aspect constraint.
    static func pickBest(boundingBoxes: [CGRect]) -> CGRect? {
        let candidates = boundingBoxes.filter { isCardAspect($0) }
        guard !candidates.isEmpty else { return nil }
        return candidates.min(by: { area($0) < area($1) })
    }

    /// Returns true when the rectangle's aspect ratio falls within the card-like
    /// range. Width/height ratio with a small guard against zero-height rects.
    static func isCardAspect(_ rect: CGRect) -> Bool {
        guard rect.height > 0.001 else { return false }
        let ratio = rect.width / rect.height
        return ratio >= minAspectRatio && ratio <= maxAspectRatio
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.width * rect.height
    }
}
