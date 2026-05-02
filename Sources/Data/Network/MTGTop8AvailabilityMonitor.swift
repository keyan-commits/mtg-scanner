import Foundation

/// Tracks the live availability of MTGTop8 so caches and UI can degrade
/// gracefully when the site is unreachable.
///
/// Behavior:
/// - Each network call to MTGTop8 reports success or failure via
///   `recordSuccess()` / `recordFailure()`.
/// - After `failureThreshold` consecutive failures, the monitor flips
///   to "unavailable" for `unavailableDuration` and any caller can
///   check `isAvailable` to skip live fetches and serve stale caches.
/// - The first success after a cool-down restores availability.
///
/// This is intentionally simpler than a textbook circuit breaker — no
/// half-open probing state. The next call after the cool-down expires
/// is the probe; if it succeeds, we're back; if it fails, we go down
/// for another `unavailableDuration`. MTGTop8 outages tend to be hours
/// or days, so this matches the real-world failure mode.
actor MTGTop8AvailabilityMonitor {

    /// Process-wide singleton used by the default `MTGTop8Service`,
    /// caches, and UI observers. Tests construct their own instance.
    static let shared = MTGTop8AvailabilityMonitor()

    private let failureThreshold: Int
    private let unavailableDuration: TimeInterval
    private let now: @Sendable () -> Date

    private var consecutiveFailures: Int = 0
    private var unavailableUntil: Date?
    /// When the most recent outage began. Used by the UI to render
    /// "Showing cached tournament data from <date>" banners.
    private var firstFailureAt: Date?

    init(
        failureThreshold: Int = 3,
        unavailableDuration: TimeInterval = 30 * 60,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.failureThreshold = failureThreshold
        self.unavailableDuration = unavailableDuration
        self.now = now
    }

    /// `true` when MTGTop8 calls should be attempted live.
    /// `false` when callers should skip the network and use cached data.
    var isAvailable: Bool {
        guard let unavailableUntil else { return true }
        return now() >= unavailableUntil
    }

    /// When the current outage started, or `nil` if MTGTop8 is healthy.
    /// Surfaced to the UI for the cached-data banner.
    var outageStartedAt: Date? {
        isAvailable ? nil : firstFailureAt
    }

    func recordSuccess() {
        consecutiveFailures = 0
        unavailableUntil = nil
        firstFailureAt = nil
    }

    func recordFailure() {
        consecutiveFailures += 1
        if firstFailureAt == nil {
            firstFailureAt = now()
        }
        if consecutiveFailures >= failureThreshold {
            unavailableUntil = now().addingTimeInterval(unavailableDuration)
        }
    }

    /// Force the monitor back into the available state. Called by the
    /// "Refresh All" toolbar action so the user can manually retry
    /// without waiting for the cool-down.
    func resetForManualRetry() {
        consecutiveFailures = 0
        unavailableUntil = nil
        firstFailureAt = nil
    }
}
