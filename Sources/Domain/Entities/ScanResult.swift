import Foundation

struct ScanResult: Sendable {
    let recognizedText: String
    let confidence: Double
    let boundingBox: CGRect
}
