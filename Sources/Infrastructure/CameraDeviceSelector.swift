import AVFoundation

/// Picks the best back-facing video device for close-up card scanning.
///
/// Why this exists: `AVCaptureDevice.default(.builtInWideAngleCamera, ...)`
/// returns the single wide-angle lens, which can't focus on subjects closer
/// than ~10cm. A card on the user's scanner stand sits well inside that
/// minimum focus distance — the wide lens locks on the background instead,
/// leaving the card blurry. Multi-lens "virtual" devices (`builtInTripleCamera`,
/// `builtInDualWideCamera`) automatically switch to the ultra-wide lens when
/// the subject gets too close, which is iOS's "auto-macro" behavior. We prefer
/// those when available and fall back to single-lens for older hardware.
enum CameraDeviceSelector {

    /// Preference order, most-capable first. Triple camera includes ultra-wide
    /// + wide + tele; dual-wide includes ultra-wide + wide. Both support
    /// auto-macro. Plain dual (wide + tele) and the single wide-angle don't,
    /// but they're better than nothing.
    static let preferenceOrder: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera,
        .builtInDualWideCamera,
        .builtInDualCamera,
        .builtInWideAngleCamera,
    ]

    /// Returns the first available device from `preferenceOrder`. The provider
    /// is injected so tests can simulate different hardware tiers without
    /// touching real `AVCaptureDevice` APIs.
    static func bestBackVideoDevice(
        provider: (AVCaptureDevice.DeviceType) -> AVCaptureDevice? = defaultProvider
    ) -> AVCaptureDevice? {
        for type in preferenceOrder {
            if let device = provider(type) {
                return device
            }
        }
        return nil
    }

    /// Reports which device type the selector would pick for a given hardware
    /// availability set. Used by tests to assert the preference order without
    /// needing real `AVCaptureDevice` instances.
    static func bestBackVideoDeviceType(
        available: Set<AVCaptureDevice.DeviceType>
    ) -> AVCaptureDevice.DeviceType? {
        preferenceOrder.first(where: { available.contains($0) })
    }

    static func defaultProvider(_ type: AVCaptureDevice.DeviceType) -> AVCaptureDevice? {
        AVCaptureDevice.default(type, for: .video, position: .back)
    }
}
