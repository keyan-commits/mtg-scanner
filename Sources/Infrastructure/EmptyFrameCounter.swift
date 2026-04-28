import Foundation

/// Counts consecutive camera frames in which no card rectangle was detected,
/// used by the live scanner to decide when the user has physically removed
/// a card from the camera view.
///
/// The contract: feed it `observe(rectanglePresent:)` once per frame. It
/// returns `true` exactly once — when the rectangle has been absent for
/// `threshold` frames in a row. Subsequent absent frames return `false`
/// until a present frame resets the counter.
struct EmptyFrameCounter: Equatable {
    let threshold: Int
    private(set) var count: Int = 0

    init(threshold: Int = 6) {
        self.threshold = threshold
    }

    /// Returns `true` on the frame that crosses the absence threshold.
    /// Once it fires, the counter resets so the caller doesn't get repeated
    /// "released" signals while the card stays out of frame.
    @discardableResult
    mutating func observe(rectanglePresent: Bool) -> Bool {
        if rectanglePresent {
            count = 0
            return false
        }
        count += 1
        if count >= threshold {
            count = 0
            return true
        }
        return false
    }

    /// Forces the counter back to zero — call when the lock is set or cleared
    /// externally so the next absence run starts fresh.
    mutating func reset() {
        count = 0
    }
}
