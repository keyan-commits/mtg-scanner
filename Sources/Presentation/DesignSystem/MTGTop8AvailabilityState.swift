import Foundation
import Observation

/// SwiftUI-friendly mirror of `MTGTop8AvailabilityMonitor`. Read by the
/// outage banner so screens can render "Showing cached tournament data
/// from <date>" without each view juggling actor `await` calls.
///
/// Refreshed by `.mtgTop8OutageBanner()` on screens that surface
/// MTGTop8 data — pulls the latest state from the actor on appear and
/// re-polls every few seconds while the screen is visible. Polling is
/// cheap (single actor read) and bounded to visible screens.
@MainActor
@Observable
final class MTGTop8AvailabilityState {

    static let shared = MTGTop8AvailabilityState()

    private(set) var isAvailable: Bool = true
    private(set) var outageStartedAt: Date?

    private let monitor: MTGTop8AvailabilityMonitor

    init(monitor: MTGTop8AvailabilityMonitor = .shared) {
        self.monitor = monitor
    }

    /// Pull the latest state from the underlying actor. Call on view
    /// appear and (lightly) while visible.
    func refresh() async {
        let available = await monitor.isAvailable
        let outageStart = await monitor.outageStartedAt
        if available != isAvailable {
            isAvailable = available
        }
        if outageStart != outageStartedAt {
            outageStartedAt = outageStart
        }
    }

    /// User-triggered "Refresh All" / pull-to-refresh: clear the outage
    /// flag immediately so the next request actually hits the network.
    func manualRetry() async {
        await monitor.resetForManualRetry()
        await refresh()
    }
}
