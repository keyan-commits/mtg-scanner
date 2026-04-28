import CoreGraphics

/// Picks the most card-like rectangle from a set of detected rectangles.
///
/// Why this exists: `VNDetectRectanglesRequest` with `maximumObservations = 1`
/// gives us whichever rectangle has highest confidence. When a card sits inside
/// a scanner stand, the stand's interior walls form a high-contrast rectangle
/// that often wins over the card itself — leaving the OCR pass running on the
/// wrong region. We bump the observation cap and pick deterministically.
///
/// Heuristic: pick the **smallest** rectangle. A card sitting inside any
/// container will always be the smaller one. Outside a stand there is only one
/// rectangle, so the rule degrades cleanly.
///
/// We deliberately do *not* run a secondary aspect-ratio filter here. The
/// `VNDetectRectanglesRequest` already filters by the rectangle's true aspect
/// at the request level; doing a second pass on the *axis-aligned* bounding
/// box rejects legitimate cards whose AABB inflates due to perspective tilt.
enum CardRectangleSelector {

    /// Returns the bounding box of the smallest rectangle in the input, or nil
    /// if the input is empty.
    static func pickBest(boundingBoxes: [CGRect]) -> CGRect? {
        guard !boundingBoxes.isEmpty else { return nil }
        return boundingBoxes.min(by: { area($0) < area($1) })
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.width * rect.height
    }
}
