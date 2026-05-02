import Testing
import Foundation
@testable import MTGCardScanner

@Suite("MTGTop8AvailabilityMonitor Tests")
struct MTGTop8AvailabilityMonitorTests {

    /// Mutable clock holder so tests can advance time between calls.
    final class Clock: @unchecked Sendable {
        var current: Date
        init(_ start: Date) { self.current = start }
    }

    private static func makeMonitor(
        failureThreshold: Int = 3,
        unavailableDuration: TimeInterval = 30 * 60,
        clock: Clock
    ) -> MTGTop8AvailabilityMonitor {
        MTGTop8AvailabilityMonitor(
            failureThreshold: failureThreshold,
            unavailableDuration: unavailableDuration,
            now: { clock.current }
        )
    }

    // MARK: - Initial state

    @Test("Starts available with no outage timestamp")
    func startsAvailable() async {
        let clock = Clock(Date(timeIntervalSince1970: 0))
        let monitor = Self.makeMonitor(clock: clock)

        #expect(await monitor.isAvailable == true)
        #expect(await monitor.outageStartedAt == nil)
    }

    // MARK: - Failures below threshold

    @Test("Single failure does not flip to unavailable")
    func singleFailureStaysAvailable() async {
        let clock = Clock(Date(timeIntervalSince1970: 0))
        let monitor = Self.makeMonitor(clock: clock)

        await monitor.recordFailure()

        #expect(await monitor.isAvailable == true)
        // Outage timestamp only meaningful once we're actually down.
        #expect(await monitor.outageStartedAt == nil)
    }

    @Test("Failures below threshold stay available")
    func belowThresholdStaysAvailable() async {
        let clock = Clock(Date(timeIntervalSince1970: 0))
        let monitor = Self.makeMonitor(failureThreshold: 3, clock: clock)

        await monitor.recordFailure()
        await monitor.recordFailure()

        #expect(await monitor.isAvailable == true)
    }

    // MARK: - Crossing the threshold

    @Test("Reaching the failure threshold flips to unavailable")
    func crossingThresholdFlipsUnavailable() async {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = Clock(start)
        let monitor = Self.makeMonitor(failureThreshold: 3, clock: clock)

        await monitor.recordFailure()
        clock.current = start.addingTimeInterval(5)
        await monitor.recordFailure()
        clock.current = start.addingTimeInterval(10)
        await monitor.recordFailure()

        #expect(await monitor.isAvailable == false)
        #expect(await monitor.outageStartedAt == start)
    }

    @Test("Outage start timestamp uses the first failure, not the threshold-crossing one")
    func outageStartTimestampIsFirstFailure() async {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let clock = Clock(start)
        let monitor = Self.makeMonitor(failureThreshold: 3, clock: clock)

        await monitor.recordFailure()  // first failure at start
        clock.current = start.addingTimeInterval(60)
        await monitor.recordFailure()
        clock.current = start.addingTimeInterval(120)
        await monitor.recordFailure()  // threshold crossed

        #expect(await monitor.outageStartedAt == start)
    }

    // MARK: - Recovery

    @Test("Success resets the failure count and restores availability")
    func successRestoresAvailability() async {
        let start = Date(timeIntervalSince1970: 3_000_000)
        let clock = Clock(start)
        let monitor = Self.makeMonitor(failureThreshold: 3, clock: clock)

        await monitor.recordFailure()
        await monitor.recordFailure()
        await monitor.recordFailure()
        #expect(await monitor.isAvailable == false)

        await monitor.recordSuccess()

        #expect(await monitor.isAvailable == true)
        #expect(await monitor.outageStartedAt == nil)
    }

    @Test("Cool-down expiry restores availability without a recorded success")
    func coolDownExpiryRestoresAvailability() async {
        let start = Date(timeIntervalSince1970: 4_000_000)
        let clock = Clock(start)
        let monitor = Self.makeMonitor(
            failureThreshold: 2,
            unavailableDuration: 60,
            clock: clock
        )

        await monitor.recordFailure()
        await monitor.recordFailure()
        #expect(await monitor.isAvailable == false)

        clock.current = start.addingTimeInterval(61)

        #expect(await monitor.isAvailable == true)
    }

    @Test("Failures during cool-down extend the outage")
    func failuresDuringCoolDownExtendOutage() async {
        let start = Date(timeIntervalSince1970: 5_000_000)
        let clock = Clock(start)
        let monitor = Self.makeMonitor(
            failureThreshold: 2,
            unavailableDuration: 60,
            clock: clock
        )

        await monitor.recordFailure()
        await monitor.recordFailure()  // unavailable until start+60

        clock.current = start.addingTimeInterval(30)
        await monitor.recordFailure()  // pushes window to start+30+60 = +90

        clock.current = start.addingTimeInterval(75)
        #expect(await monitor.isAvailable == false)

        clock.current = start.addingTimeInterval(91)
        #expect(await monitor.isAvailable == true)
    }

    // MARK: - Manual retry

    @Test("Manual retry clears unavailability immediately")
    func manualRetryClearsUnavailability() async {
        let start = Date(timeIntervalSince1970: 6_000_000)
        let clock = Clock(start)
        let monitor = Self.makeMonitor(
            failureThreshold: 2,
            unavailableDuration: 1_000_000,
            clock: clock
        )

        await monitor.recordFailure()
        await monitor.recordFailure()
        #expect(await monitor.isAvailable == false)

        await monitor.resetForManualRetry()

        #expect(await monitor.isAvailable == true)
        #expect(await monitor.outageStartedAt == nil)
    }
}
