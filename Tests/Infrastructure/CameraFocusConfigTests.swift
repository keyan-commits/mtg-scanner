import Testing
import AVFoundation
@testable import MTGCardScanner

@Suite("CameraFocusConfig")
struct CameraFocusConfigTests {

    @Test("Fully-capable device gets continuous AF + near range + continuous AE + subject-area monitoring")
    func fullyCapable() {
        let caps = CameraFocusConfig.Capabilities(
            supportsContinuousAutoFocus: true,
            supportsAutoFocusRangeRestriction: true,
            supportsContinuousAutoExposure: true
        )
        let config = CameraFocusConfig.bestFor(capabilities: caps)
        #expect(config.focusMode == .continuousAutoFocus)
        #expect(config.rangeRestriction == .near)
        #expect(config.exposureMode == .continuousAutoExposure)
        #expect(config.subjectAreaChangeMonitoring == true)
    }

    @Test("Device without continuous AF leaves focusMode unset")
    func noContinuousAutoFocus() {
        let caps = CameraFocusConfig.Capabilities(
            supportsContinuousAutoFocus: false,
            supportsAutoFocusRangeRestriction: true,
            supportsContinuousAutoExposure: true
        )
        let config = CameraFocusConfig.bestFor(capabilities: caps)
        #expect(config.focusMode == nil)
        #expect(config.rangeRestriction == .near)
        #expect(config.exposureMode == .continuousAutoExposure)
    }

    @Test("Device without near-range restriction leaves rangeRestriction unset")
    func noRangeRestriction() {
        let caps = CameraFocusConfig.Capabilities(
            supportsContinuousAutoFocus: true,
            supportsAutoFocusRangeRestriction: false,
            supportsContinuousAutoExposure: true
        )
        let config = CameraFocusConfig.bestFor(capabilities: caps)
        #expect(config.focusMode == .continuousAutoFocus)
        #expect(config.rangeRestriction == nil)
    }

    @Test("Device without continuous AE leaves exposureMode unset")
    func noContinuousAutoExposure() {
        let caps = CameraFocusConfig.Capabilities(
            supportsContinuousAutoFocus: true,
            supportsAutoFocusRangeRestriction: true,
            supportsContinuousAutoExposure: false
        )
        let config = CameraFocusConfig.bestFor(capabilities: caps)
        #expect(config.exposureMode == nil)
    }

    @Test("Subject-area monitoring is always requested regardless of capabilities")
    func subjectAreaAlwaysOn() {
        let none = CameraFocusConfig.Capabilities(
            supportsContinuousAutoFocus: false,
            supportsAutoFocusRangeRestriction: false,
            supportsContinuousAutoExposure: false
        )
        let config = CameraFocusConfig.bestFor(capabilities: none)
        #expect(config.subjectAreaChangeMonitoring == true)
        // Sanity: no other capabilities, no other modes set.
        #expect(config.focusMode == nil)
        #expect(config.rangeRestriction == nil)
        #expect(config.exposureMode == nil)
    }
}
