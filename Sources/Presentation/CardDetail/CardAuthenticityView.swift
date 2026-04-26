import SwiftUI

/// Card authenticity checker using Gemini Vision.
/// Analyzes a card photo and returns a checklist of authenticity tests.
struct CardAuthenticityView: View {

    let card: Card

    @State private var showCamera: Bool = false
    @State private var selectedImage: UIImage?
    @State private var isAnalyzing: Bool = false
    @State private var results: [AuthCheck] = []
    @State private var overallVerdict: String?
    @State private var error: String?

    struct AuthCheck: Identifiable {
        let id = UUID()
        let test: String
        let status: Status
        let detail: String

        enum Status: String {
            case pass = "PASS"
            case fail = "FAIL"
            case warning = "WARNING"
            case unknown = "UNKNOWN"
        }
    }

    private var isConfigured: Bool { GeminiVisionService.isConfigured }

    var body: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Authenticity Check")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                    Spacer()
                }

                if !results.isEmpty {
                    // Overall verdict
                    if let verdict = overallVerdict {
                        Text(verdict)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(verdictColor)
                            .padding(.bottom, 4)
                    }

                    // Checklist
                    ForEach(results) { check in
                        HStack(spacing: 10) {
                            statusIcon(check.status)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(check.test)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(MD3Theme.onSurface)
                                Text(check.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }

                    // Disclaimer
                    Text("Visual analysis only. Not a substitute for physical tests (light, bend, weight). High-quality counterfeits may pass visual checks.")
                        .font(.system(size: 9))
                        .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.6))
                        .padding(.top, 4)

                    // Re-check button
                    Button {
                        showCamera = true
                    } label: {
                        Text("Re-check with new photo")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MD3Theme.primary)
                    }
                    .buttonStyle(.plain)
                } else if isAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Analyzing card authenticity…")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                } else if !isConfigured {
                    Text("Set up Gemini API key in Settings to enable authenticity checks")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                } else {
                    Button {
                        showCamera = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield")
                            Text("Check Authenticity")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Text("Take a close-up photo of the card for visual analysis")
                        .font(.system(size: 9))
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                Task { await analyzeAuthenticity(image: image) }
            }
        }
    }

    // MARK: - Status Icons

    @ViewBuilder
    private func statusIcon(_ status: AuthCheck.Status) -> some View {
        switch status {
        case .pass:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 18))
        case .fail:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 18))
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 18))
        case .unknown:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.gray)
                .font(.system(size: 18))
        }
    }

    private var verdictColor: Color {
        let fails = results.filter { $0.status == .fail }.count
        let warnings = results.filter { $0.status == .warning }.count
        if fails > 0 { return .red }
        if warnings > 1 { return .orange }
        return .green
    }

    // MARK: - Analysis

    private func analyzeAuthenticity(image: UIImage) async {
        isAnalyzing = true
        error = nil
        results = []
        overallVerdict = nil
        defer { isAnalyzing = false }

        guard let cgImage = image.cgImage else {
            error = "Could not process image"
            return
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            error = "Could not encode image"
            return
        }
        let base64 = jpegData.base64EncodedString()

        guard let apiKey = GeminiVisionService.activeApiKey else {
            error = "No API key configured"
            return
        }

        let prompt = """
        Analyze this Magic: The Gathering card photo for authenticity. The card should be: \(card.name) from \(card.set.name).

        Check each of these tests and return ONLY a JSON object:
        {"verdict":"LIKELY AUTHENTIC or LIKELY FAKE or INCONCLUSIVE","checks":[{"test":"test name","status":"PASS or FAIL or WARNING or UNKNOWN","detail":"brief explanation"}]}

        Tests to perform:
        1. Print Quality — text sharpness, clean edges, no bleeding
        2. Color Accuracy — correct color saturation for this era/set
        3. Border Quality — consistent width, correct color (black/white)
        4. Set Symbol — correct shape, color, and rarity indicator
        5. Holographic Stamp — present on rares/mythics (post-2014 only)
        6. Font Consistency — correct MTG fonts for card name, type, text
        7. Card Stock — visible texture appropriate for real cards
        8. Rosette Pattern — dot pattern visible (if close-up enough)

        Mark as UNKNOWN if the photo quality prevents assessment. Be honest about what you can and cannot determine from the image.
        """

        let url = URL(string: "\(GeminiVisionService.endpointURL)?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": prompt]
                ]
            ]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            error = "Failed to build request"
            return
        }
        request.httpBody = bodyData
        GeminiVisionService.recordUsage()

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                error = "Rate limited. Try again in a minute."
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                error = "Unexpected response from Gemini"
                return
            }

            let cleaned = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let resultData = cleaned.data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                error = "Could not parse response"
                return
            }

            overallVerdict = result["verdict"] as? String ?? "INCONCLUSIVE"
            let checks = result["checks"] as? [[String: String]] ?? []
            results = checks.compactMap { dict in
                guard let test = dict["test"],
                      let statusStr = dict["status"],
                      let detail = dict["detail"],
                      let status = AuthCheck.Status(rawValue: statusStr) else { return nil }
                return AuthCheck(test: test, status: status, detail: detail)
            }

            if results.isEmpty {
                error = "No checks returned. Try with a clearer photo."
            }
        } catch {
            self.error = "Request failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
