import AVFoundation
import CoreImage
import Vision
import UIKit

/// Manages the AVCaptureSession with real-time rectangle detection and frame OCR.
/// Identifies card names directly from video frames for instant results.
@MainActor
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State

    enum ScanState: Equatable {
        case idle
        case detecting       // Rectangle found, no OCR yet
        case reading(String) // OCR read a name from the frame
        case confirmed       // Card identified and added to list
    }

    @Published var scanState: ScanState = .idle
    @Published var detectedQuad: [CGPoint]?
    @Published var recognizedCardName: String?
    @Published var confirmedCardName: String? // Set when DB-validated for N frames

    // MARK: - AVFoundation

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.mtgscanner.camera", qos: .userInitiated)

    // MARK: - Vision (nonisolated for background queue access)

    private nonisolated(unsafe) lazy var rectangleRequest: VNDetectRectanglesRequest = {
        let req = VNDetectRectanglesRequest()
        // Card-like aspect range. Vision filters at the request level; we then
        // tighten further inside CardRectangleSelector when picking among
        // multiple candidates so squarish container rectangles get rejected.
        req.minimumAspectRatio = 0.55
        req.maximumAspectRatio = 0.85
        req.minimumSize = 0.15
        // Bumped from 1 — allows us to see both the card AND any container
        // rectangle (e.g. a scanner stand's interior), then pick the card.
        req.maximumObservations = 5
        req.minimumConfidence = 0.7
        req.quadratureTolerance = 20
        return req
    }()

    // MARK: - Frame Processing

    private nonisolated(unsafe) var isProcessingFrame = false
    private var consecutiveNames: [String] = []
    private let confirmCount = 3
    private var isConfirmed = false
    /// Counts frames where no rectangle was detected; used to auto-release the
    /// post-confirmation lock when the user physically removes the card.
    private var emptyFrames = EmptyFrameCounter(threshold: 6)

    // MARK: - Setup

    func configure() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        // Prefer multi-lens virtual cameras so iOS can auto-engage the
        // ultra-wide for macro when a card is close to the lens (e.g. on a
        // scanner stand). Falls back to wide-angle on older hardware.
        guard let device = CameraDeviceSelector.bestBackVideoDevice(),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        print("[Camera] Using device type: \(device.deviceType.rawValue)")

        if session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }

        session.commitConfiguration()

        configureFocus(on: device)
        captureDevice = device
        subscribeToSubjectAreaChanges()
    }

    /// Holds the current capture device so we can re-issue focus commands
    /// (subject-area change handler, tap-to-focus).
    private var captureDevice: AVCaptureDevice?

    /// Applies focus / exposure settings tuned for close-up card scanning.
    /// Cards sit ~10–25cm from the lens; restricting AF to "near" stops the
    /// system hunting toward infinity, and continuous exposure keeps the
    /// reading legible as ambient light shifts. Subject-area change
    /// monitoring lets us notice when a new card slides in and re-focus.
    /// On iOS 16+ multi-lens devices we also bias the constituent-device
    /// switcher toward auto-macro so the ultra-wide engages reliably when
    /// the card is on a scanner stand.
    private func configureFocus(on device: AVCaptureDevice) {
        let config = CameraFocusConfig.bestFor(device: device)
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if let mode = config.focusMode { device.focusMode = mode }
            if let restriction = config.rangeRestriction { device.autoFocusRangeRestriction = restriction }
            if let exposure = config.exposureMode { device.exposureMode = exposure }
            device.isSubjectAreaChangeMonitoringEnabled = config.subjectAreaChangeMonitoring

            if #available(iOS 16, *) {
                // For virtual multi-lens devices (.builtInTripleCamera /
                // .builtInDualWideCamera), .auto lets the system swap to the
                // ultra-wide constituent for macro distances. The default is
                // already .auto, but setting it explicitly ensures we don't
                // inherit a restricted behavior from elsewhere.
                if !device.constituentDevices.isEmpty {
                    device.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
                }
            }
        } catch {
            print("[Camera] Focus config failed: \(error.localizedDescription)")
        }
    }

    private func subscribeToSubjectAreaChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSubjectAreaChange),
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: nil
        )
    }

    @objc private func handleSubjectAreaChange() {
        guard let device = captureDevice else { return }
        // A scene change usually means the user moved to a new card. Re-trigger
        // focus and exposure at the centre so the new subject snaps sharp.
        focus(at: CGPoint(x: 0.5, y: 0.5), holdAutoMode: false)
    }

    /// Focuses the camera at a point in normalized 0–1 coordinates (Vision
    /// space — top-left origin). Used by tap-to-focus and the subject-area
    /// change handler.
    nonisolated func focus(at point: CGPoint, holdAutoMode: Bool = true) {
        Task { @MainActor [weak self] in
            guard let device = self?.captureDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                }
                if holdAutoMode {
                    device.isSubjectAreaChangeMonitoringEnabled = true
                }
            } catch {
                print("[Camera] focus(at:) failed: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        guard !session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        processingQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func reset() {
        detectedQuad = nil
        recognizedCardName = nil
        confirmedCardName = nil
        consecutiveNames.removeAll()
        isConfirmed = false
        emptyFrames.reset()
        scanState = .idle
    }

    // MARK: - Frame OCR

    private nonisolated func runFrameOCR(pixelBuffer: CVPixelBuffer, cardRect: CGRect) -> String? {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["en"]
        textRequest.usesLanguageCorrection = false
        // OCR the full card region — let the name extractor pick the right line
        textRequest.regionOfInterest = cardRect

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([textRequest])

        guard let results = textRequest.results, !results.isEmpty else {
            print("[LiveOCR] No text found in card region")
            return nil
        }

        // Find the topmost text line (highest y in Vision coords = top of card = card name)
        let sorted = results.sorted { ($0.topCandidates(1).first != nil ? $0.boundingBox.origin.y : 0) >
                                       ($1.topCandidates(1).first != nil ? $1.boundingBox.origin.y : 0) }

        for result in sorted {
            guard let text = result.topCandidates(1).first?.string else { continue }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "  ", with: " ")
            // Card names: 3-40 chars, no common non-name patterns
            guard cleaned.count >= 3, cleaned.count <= 40 else { continue }
            let lower = cleaned.lowercased()
            if lower.contains("summon") || lower.contains("instant") || lower.contains("sorcery")
                || lower.contains("creature") || lower.contains("artifact") || lower.contains("enchant")
                || lower.contains("illus") || lower.contains("wizard") || lower.contains("land")
                || lower.contains("//") || lower.contains("©") { continue }
            print("[LiveOCR] Read: '\(cleaned)'")
            return cleaned
        }
        return nil
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessingFrame = false
            return
        }

        // Step 1: Detect card rectangle
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([rectangleRequest])
        } catch {
            isProcessingFrame = false
            return
        }

        // Among the rectangles Vision found, pick the most card-like one — the
        // smallest one whose aspect matches an MTG card. Prevents the OCR pass
        // from running on the stand-interior rectangle when the card is inside
        // a holder.
        let allObservations = rectangleRequest.results ?? []
        let pickedBox = CardRectangleSelector.pickBest(boundingBoxes: allObservations.map(\.boundingBox))
        let observation = allObservations.first(where: { $0.boundingBox == pickedBox })

        // Step 2: Run fast OCR on card name region
        var ocrName: String?
        if let obs = observation {
            ocrName = runFrameOCR(pixelBuffer: pixelBuffer, cardRect: obs.boundingBox)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            if let obs = observation {
                self.detectedQuad = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
                self.emptyFrames.observe(rectanglePresent: true)

                if let name = ocrName, !self.isConfirmed {
                    self.recognizedCardName = name
                    self.scanState = .reading(name)

                    // Track consecutive matches (fuzzy — first 5 chars must match)
                    let nameKey = String(name.lowercased().prefix(5))
                    self.consecutiveNames.append(nameKey)
                    if self.consecutiveNames.count > self.confirmCount + 2 {
                        self.consecutiveNames.removeFirst()
                    }

                    let recent = Array(self.consecutiveNames.suffix(self.confirmCount))
                    if recent.count == self.confirmCount {
                        let target = recent.last!
                        let allMatch = recent.allSatisfy { $0 == target }
                        if allMatch {
                            self.confirmedCardName = name
                            self.isConfirmed = true
                            self.scanState = .confirmed
                            print("[LiveOCR] Confirmed: '\(name)'")
                        }
                    }
                }
            } else {
                self.detectedQuad = nil
                self.recognizedCardName = nil
                self.consecutiveNames.removeAll()
                if self.isConfirmed {
                    // Card was committed; wait for it to leave the frame for
                    // a sustained run before re-engaging the scanner.
                    if self.emptyFrames.observe(rectanglePresent: false) {
                        self.confirmedCardName = nil
                        self.isConfirmed = false
                        self.scanState = .idle
                        print("[LiveOCR] Card removed — ready for next scan")
                    }
                } else {
                    self.scanState = .idle
                }
            }

            self.isProcessingFrame = false
        }
    }
}
