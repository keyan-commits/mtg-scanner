import Foundation
import CoreGraphics
import UIKit

/// Identifies Magic: The Gathering cards using Google's Gemini Vision API.
/// Used as a fallback when the local pipeline (OCR + visual search) fails.
/// Free tier: 15 requests/minute, 1,500/day.
actor GeminiVisionService {

    private static let apiKeyKey = "geminiAPIKey"
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    static var apiKey: String? {
        get { UserDefaults.standard.string(forKey: apiKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }

    static var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Identifies a card from a CGImage. Returns (cardName, setCode?, collectorNumber?) or nil.
    func identifyCard(image: CGImage) async -> GeminiCardResult? {
        guard let apiKey = Self.apiKey, !apiKey.isEmpty else { return nil }

        // Convert to JPEG
        let uiImage = UIImage(cgImage: image)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else { return nil }
        let base64 = jpegData.base64EncodedString()

        // Build request
        guard let url = URL(string: "\(Self.endpoint)?key=\(apiKey)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let prompt = """
        Identify this Magic: The Gathering card. Return ONLY a JSON object with these fields:
        {"card_name": "exact English card name", "set_code": "3-letter Scryfall set code or null", "collector_number": "collector number or null"}
        Do not include any other text, explanation, or markdown. Just the raw JSON object.
        """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": prompt]
                ]
            ]]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[Gemini] HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }

            // Parse Gemini response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                print("[Gemini] Failed to parse response")
                return nil
            }

            // Extract JSON from response (Gemini sometimes wraps in markdown)
            let cleaned = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let resultData = cleaned.data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                  let cardName = result["card_name"] as? String else {
                print("[Gemini] Failed to parse card result from: \(text)")
                return nil
            }

            let setCode = result["set_code"] as? String
            let collectorNumber = result["collector_number"] as? String

            print("[Gemini] Identified: \(cardName) [\(setCode ?? "?")] #\(collectorNumber ?? "?")")
            return GeminiCardResult(
                cardName: cardName,
                setCode: setCode,
                collectorNumber: collectorNumber
            )
        } catch {
            print("[Gemini] Request failed: \(error.localizedDescription)")
            return nil
        }
    }
}

struct GeminiCardResult {
    let cardName: String
    let setCode: String?
    let collectorNumber: String?
}
