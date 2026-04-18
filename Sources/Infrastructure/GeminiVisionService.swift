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

    private static let enabledKey = "geminiEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether Gemini should be used right now (configured + enabled + within limit).
    static var isActive: Bool {
        isConfigured && isEnabled && !isDailyLimitReached
    }

    // MARK: - Daily Usage Tracking

    private static let dailyLimitKey = "geminiDailyCount"
    private static let dailyDateKey = "geminiDailyDate"
    private static let dailyLimit = 1500

    /// Number of Gemini requests made today.
    static var dailyUsage: Int {
        resetIfNewDay()
        return UserDefaults.standard.integer(forKey: dailyLimitKey)
    }

    /// Whether the daily free-tier limit has been reached.
    static var isDailyLimitReached: Bool {
        dailyUsage >= dailyLimit
    }

    /// Records one API usage. Call after a successful Gemini response.
    static func recordUsage() {
        resetIfNewDay()
        let count = UserDefaults.standard.integer(forKey: dailyLimitKey)
        UserDefaults.standard.set(count + 1, forKey: dailyLimitKey)
    }

    private static func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let stored = UserDefaults.standard.double(forKey: dailyDateKey)
        if stored < today {
            UserDefaults.standard.set(0, forKey: dailyLimitKey)
            UserDefaults.standard.set(today, forKey: dailyDateKey)
        }
    }

    /// Identifies a card from a CGImage. Returns (cardName, setCode?, collectorNumber?) or nil.
    func identifyCard(image: CGImage) async -> GeminiCardResult? {
        guard let apiKey = Self.apiKey, !apiKey.isEmpty else { return nil }
        Self.recordUsage()

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
                collectorNumber: collectorNumber,
                boundingBox: nil
            )
        } catch {
            print("[Gemini] Request failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Identifies ALL cards in a full binder page photo. Returns an array of results.
    /// Uses a single API call instead of one per card.
    func identifyAllCards(image: CGImage) async -> [GeminiCardResult]? {
        guard let apiKey = Self.apiKey, !apiKey.isEmpty else { return nil }
        Self.recordUsage()

        let uiImage = UIImage(cgImage: image)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.6) else { return nil }
        let base64 = jpegData.base64EncodedString()

        guard let url = URL(string: "\(Self.endpoint)?key=\(apiKey)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let prompt = """
        Identify ALL Magic: The Gathering cards visible in this photo.
        For each card, determine:
        1. The exact English card name
        2. The Scryfall 3-letter set code (if readable)
        3. The collector number (if readable)
        4. The bounding box as fractional coordinates (0.0-1.0) relative to image width/height: x (left edge), y (top edge), w (width), h (height)

        Cards may be in sleeves or at angles. Include duplicates — if you see 4 copies of the same card, list it 4 times.
        Return ONLY a JSON array (no other text or markdown):
        [{"card_name": "exact name", "set_code": "abc", "collector_number": "123", "x": 0.0, "y": 0.0, "w": 0.25, "h": 0.33}, ...]
        Order the cards left-to-right, top-to-bottom as they appear in the photo.
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
                print("[Gemini] Batch HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                print("[Gemini] Batch: failed to parse response")
                return nil
            }

            let cleaned = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let resultData = cleaned.data(using: .utf8),
                  let array = try JSONSerialization.jsonObject(with: resultData) as? [[String: Any]] else {
                print("[Gemini] Batch: failed to parse JSON array from: \(text.prefix(200))")
                return nil
            }

            let results = array.compactMap { item -> GeminiCardResult? in
                guard let name = item["card_name"] as? String else { return nil }
                var bbox: (x: Double, y: Double, w: Double, h: Double)?
                if let x = item["x"] as? Double,
                   let y = item["y"] as? Double,
                   let w = item["w"] as? Double,
                   let h = item["h"] as? Double,
                   w > 0 && h > 0 {
                    bbox = (x: x, y: y, w: w, h: h)
                }
                return GeminiCardResult(
                    cardName: name,
                    setCode: item["set_code"] as? String,
                    collectorNumber: item["collector_number"] as? String,
                    boundingBox: bbox
                )
            }

            print("[Gemini] Batch: identified \(results.count) cards")
            return results
        } catch {
            print("[Gemini] Batch request failed: \(error.localizedDescription)")
            return nil
        }
    }
}

struct GeminiCardResult {
    let cardName: String
    let setCode: String?
    let collectorNumber: String?
    /// Bounding box as fractional coordinates (0-1) relative to image dimensions.
    /// (x, y) is top-left corner; (w, h) is width and height.
    let boundingBox: (x: Double, y: Double, w: Double, h: Double)?
}
