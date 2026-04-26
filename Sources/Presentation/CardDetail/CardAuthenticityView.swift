import SwiftUI
import PhotosUI

/// Card authenticity checker using Gemini Vision.
/// Supports front and back photos via system camera or photo library.
/// Can be used standalone (from home) or embedded in card detail.
struct CardAuthenticityView: View {

    /// Optional — when provided, tells Gemini what card to expect.
    let card: Card?

    @State private var frontImage: UIImage?
    @State private var backImage: UIImage?
    @State private var showFrontPicker: Bool = false
    @State private var showBackPicker: Bool = false
    @State private var isAnalyzing: Bool = false
    @State private var results: [AuthCheck] = []
    @State private var overallVerdict: String?
    @State private var error: String?
    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?

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
    private var hasPhotos: Bool { frontImage != nil || backImage != nil }

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
                    resultsList
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
                    photoButtons
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .onChange(of: frontItem) { _, item in
            Task { await loadPhoto(item: item, target: .front) }
        }
        .onChange(of: backItem) { _, item in
            Task { await loadPhoto(item: item, target: .back) }
        }
    }

    // MARK: - Photo Buttons

    private var photoButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Front photo
                PhotosPicker(selection: $frontItem, matching: .images) {
                    VStack(spacing: 6) {
                        if let frontImage {
                            Image(uiImage: frontImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(MD3Theme.surfaceVariant)
                                .frame(width: 80, height: 112)
                                .overlay(
                                    VStack(spacing: 4) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.title3)
                                        Text("Front")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                                )
                        }
                    }
                }

                // Back photo
                PhotosPicker(selection: $backItem, matching: .images) {
                    VStack(spacing: 6) {
                        if let backImage {
                            Image(uiImage: backImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(MD3Theme.surfaceVariant)
                                .frame(width: 80, height: 112)
                                .overlay(
                                    VStack(spacing: 4) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.title3)
                                        Text("Back")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                                )
                        }
                    }
                }

                Spacer()
            }

            if hasPhotos {
                Button {
                    Task { await analyzeAuthenticity() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield")
                        Text("Verify Card")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            Text("Pick front and/or back photos from library or camera")
                .font(.system(size: 9))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let verdict = overallVerdict {
                Text(verdict)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(verdictColor)
                    .padding(.bottom, 2)
            }

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

            Text("Visual analysis only. Not a substitute for physical tests (light, bend, weight).")
                .font(.system(size: 9))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.6))
                .padding(.top, 4)

            Button {
                results = []
                overallVerdict = nil
                frontImage = nil
                backImage = nil
                frontItem = nil
                backItem = nil
            } label: {
                Text("Check another card")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MD3Theme.primary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: AuthCheck.Status) -> some View {
        switch status {
        case .pass:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.system(size: 18))
        case .fail:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red).font(.system(size: 18))
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.system(size: 18))
        case .unknown:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.gray).font(.system(size: 18))
        }
    }

    private var verdictColor: Color {
        let fails = results.filter { $0.status == .fail }.count
        if fails > 0 { return .red }
        if results.filter({ $0.status == .warning }).count > 1 { return .orange }
        return .green
    }

    // MARK: - Photo Loading

    private enum PhotoTarget { case front, back }

    private func loadPhoto(item: PhotosPickerItem?, target: PhotoTarget) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        switch target {
        case .front: frontImage = image
        case .back: backImage = image
        }
    }

    // MARK: - Analysis

    private func analyzeAuthenticity() async {
        isAnalyzing = true
        error = nil
        results = []
        overallVerdict = nil
        defer { isAnalyzing = false }

        guard let apiKey = GeminiVisionService.activeApiKey else {
            error = "No API key configured"
            return
        }

        var parts: [[String: Any]] = []

        // Add front photo
        if let frontImage, let jpeg = frontImage.jpegData(compressionQuality: 0.8) {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }

        // Add back photo
        if let backImage, let jpeg = backImage.jpegData(compressionQuality: 0.8) {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }

        guard !parts.isEmpty else {
            error = "Select at least one photo"
            return
        }

        let cardContext = card.map { "The card should be: \($0.name) from \($0.set.name)." } ?? "Identify and verify this Magic: The Gathering card."
        let photoContext = frontImage != nil && backImage != nil
            ? "Both front and back photos provided."
            : (frontImage != nil ? "Front photo only." : "Back photo only.")

        let prompt = """
        Analyze this Magic: The Gathering card for authenticity. \(cardContext) \(photoContext)

        Return ONLY JSON: {"verdict":"LIKELY AUTHENTIC or LIKELY FAKE or INCONCLUSIVE","checks":[{"test":"name","status":"PASS/FAIL/WARNING/UNKNOWN","detail":"brief explanation"}]}

        Tests (mark UNKNOWN if photo doesn't show that area):
        1. Print Quality — text sharpness, clean edges, no ink bleeding
        2. Color Accuracy — correct saturation for this set/era
        3. Border Quality — consistent width, correct color
        4. Set Symbol — correct shape and rarity color
        5. Holographic Stamp — present on rares/mythics (post-2014)
        6. Font Consistency — correct MTG fonts
        7. Card Back — correct blue color, pattern, and print quality
        8. Rosette Pattern — visible dot pattern under close inspection
        Be honest about what you can and cannot determine.
        """

        parts.append(["text": prompt])

        let url = URL(string: "\(GeminiVisionService.endpointURL)?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "contents": [["parts": parts]]
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
                  let respParts = content["parts"] as? [[String: Any]],
                  let text = respParts.first?["text"] as? String else {
                error = "Unexpected response"
                return
            }

            let cleaned = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let resultData = cleaned.data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                error = "Could not parse response. Try again."
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

            if results.isEmpty { error = "No checks returned. Try a clearer photo." }
        } catch {
            self.error = "Request failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Standalone Screen (from Home)

struct CardAuthenticityScreen: View {
    var body: some View {
        ScrollView {
            CardAuthenticityView(card: nil)
                .padding(16)
        }
        .background(MD3Theme.background)
        .navigationTitle("Verify Card")
        .navigationBarTitleDisplayMode(.inline)
    }
}
