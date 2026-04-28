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
        req.minimumAspectRatio = 0.55
        req.maximumAspectRatio = 0.85
        req.minimumSize = 0.15
        req.maximumObservations = 1
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

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }

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

        let observation = rectangleRequest.results?.first

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
