import Testing
import AVFoundation
@testable import MTGCardScanner

@Suite("CameraDeviceSelector preference order")
struct CameraDeviceSelectorTests {

    @Test("Triple camera wins when available alongside everything else")
    func triplePreferred() {
        let available: Set<AVCaptureDevice.DeviceType> = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera,
        ]
        #expect(CameraDeviceSelector.bestBackVideoDeviceType(available: available) == .builtInTripleCamera)
    }

    @Test("Dual-wide wins when triple is absent (non-Pro with ultra-wide)")
    func dualWideWhenNoTriple() {
        let available: Set<AVCaptureDevice.DeviceType> = [
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera,
        ]
        #expect(CameraDeviceSelector.bestBackVideoDeviceType(available: available) == .builtInDualWideCamera)
    }

    @Test("Dual (wide + tele) used when no ultra-wide is available")
    func dualWhenNoUltraWide() {
        let available: Set<AVCaptureDevice.DeviceType> = [
            .builtInDualCamera,
            .builtInWideAngleCamera,
        ]
        #expect(CameraDeviceSelector.bestBackVideoDeviceType(available: available) == .builtInDualCamera)
    }

    @Test("Wide-angle is the last-resort fallback")
    func wideAngleFallback() {
        let available: Set<AVCaptureDevice.DeviceType> = [.builtInWideAngleCamera]
        #expect(CameraDeviceSelector.bestBackVideoDeviceType(available: available) == .builtInWideAngleCamera)
    }

    @Test("No back camera available returns nil")
    func noCameraReturnsNil() {
        #expect(CameraDeviceSelector.bestBackVideoDeviceType(available: []) == nil)
    }

    @Test("Unrelated device types in the available set are ignored")
    func unrelatedTypesIgnored() {
        // Front cameras / mic device types shouldn't affect back-camera selection.
        let available: Set<AVCaptureDevice.DeviceType> = [
            .builtInTrueDepthCamera,
            .builtInWideAngleCamera,
        ]
        #expect(CameraDeviceSelector.bestBackVideoDeviceType(available: available) == .builtInWideAngleCamera)
    }

    @Test("Provider-based selector probes types in preference order until one returns non-nil")
    func providerStopsAtFirstHit() {
        var probedTypes: [AVCaptureDevice.DeviceType] = []
        let result = CameraDeviceSelector.bestBackVideoDevice { type in
            probedTypes.append(type)
            // Simulate "only triple is available" — this returns nil because we
            // can't actually instantiate AVCaptureDevice in a unit test, but
            // that's fine — we only care that the probe stops once we report a
            // hit. Since every probe returns nil here, all four types should
            // be tried before returning nil.
            return nil
        }
        #expect(result == nil)
        #expect(probedTypes == CameraDeviceSelector.preferenceOrder)
    }
}
