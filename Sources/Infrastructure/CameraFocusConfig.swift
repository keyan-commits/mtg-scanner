import AVFoundation

/// Tunable focus/exposure parameters for the live card scanner. Computed by
/// inspecting the capabilities of an `AVCaptureDevice` so we never set a mode
/// the device rejects. Pure data — extracted from `CameraManager.configureFocus`
/// so the choice can be unit-tested without standing up a real capture session.
struct CameraFocusConfig: Equatable {
    var focusMode: AVCaptureDevice.FocusMode?
    var rangeRestriction: AVCaptureDevice.AutoFocusRangeRestriction?
    var exposureMode: AVCaptureDevice.ExposureMode?
    var subjectAreaChangeMonitoring: Bool

    /// Capability inputs — abstract over `AVCaptureDevice` so the helper is
    /// pure and testable.
    struct Capabilities {
        var supportsContinuousAutoFocus: Bool
        var supportsAutoFocusRangeRestriction: Bool
        var supportsContinuousAutoExposure: Bool
    }

    static func bestFor(capabilities: Capabilities) -> CameraFocusConfig {
        CameraFocusConfig(
            focusMode: capabilities.supportsContinuousAutoFocus ? .continuousAutoFocus : nil,
            // Cards are ~10–25cm from the lens. Telling AF "near only" stops it
            // hunting toward infinity, which speeds up lock-on and reduces the
            // visible focus pulse.
            rangeRestriction: capabilities.supportsAutoFocusRangeRestriction ? .near : nil,
            exposureMode: capabilities.supportsContinuousAutoExposure ? .continuousAutoExposure : nil,
            subjectAreaChangeMonitoring: true
        )
    }

    static func bestFor(device: AVCaptureDevice) -> CameraFocusConfig {
        let caps = Capabilities(
            supportsContinuousAutoFocus: device.isFocusModeSupported(.continuousAutoFocus),
            supportsAutoFocusRangeRestriction: device.isAutoFocusRangeRestrictionSupported,
            supportsContinuousAutoExposure: device.isExposureModeSupported(.continuousAutoExposure)
        )
        return bestFor(capabilities: caps)
    }
}
