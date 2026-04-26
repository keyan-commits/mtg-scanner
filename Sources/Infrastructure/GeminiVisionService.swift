import Foundation
import CoreGraphics
import UIKit

/// Identifies Magic: The Gathering cards using Google's Gemini Vision API.
/// Used as a fallback when the local pipeline (OCR + visual search) fails.
/// Free tier: 15 requests/minute, 1,500/day.
actor GeminiVisionService {

    private static let apiKeyKey = "geminiAPIKey"
    // Gemini 3 Flash Preview: 15 RPM, 1000 RPD free tier
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent"

    static var apiKey: String? {
        get { UserDefaults.standard.string(forKey: apiKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }

    private static let enabledKey = "geminiEnabled"

    static var isEnabled: Bool {
        get {
            // Default to true if key exists but user never toggled
            if UserDefaults.standard.object(forKey: enabledKey) == nil && isConfigured {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// The full endpoint URL (for test connection and shared access).
    static var endpointURL: String { endpoint }

    static var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether Gemini should be used right now (configured + enabled + within limit + not rate-limited).
    static var isActive: Bool {
        isConfigured && isEnabled && !isDailyLimitReached && !isRateLimited
    }

    /// Last error message from Gemini (shown to user).
    static var lastError: String? {
        get { UserDefaults.standard.string(forKey: "geminiLastError") }
        set { UserDefaults.standard.set(newValue, forKey: "geminiLastError") }
    }

    /// Whether Gemini hit a rate limit (429) — auto-resets after 60 seconds.
    private static var isRateLimited: Bool {
        let rateLimitedAt = UserDefaults.standard.double(forKey: "geminiRateLimitedAt")
        guard rateLimitedAt > 0 else { return false }
        return Date().timeIntervalSince1970 - rateLimitedAt < 60
    }

    private static func markRateLimited() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "geminiRateLimitedAt")
    }

    // MARK: - Daily Usage Tracking

    private static let dailyLimitKey = "geminiDailyCount"
    private static let dailyDateKey = "geminiDailyDate"
    // Gemini 3 Flash Preview free tier: 15 RPM, 1000 RPD
    private static let dailyLimit = 1000

    /// Number of Gemini requests made today.
    static var dailyUsage: Int {
        resetIfNewDay()
        return UserDefaults.standard.integer(forKey: dailyLimitKey)
    }

    /// Whether the daily free-tier limit has been reached.
    static var isDailyLimitReached: Bool {
        dailyUsage >= dailyLimit
    }

    /// Manually sets the daily usage count (for syncing with Google's dashboard).
    static func setDailyUsage(_ count: Int) {
        resetIfNewDay()
        UserDefaults.standard.set(count, forKey: dailyLimitKey)
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
        {"card_name": "exact English card name", "set_code": "3-letter Scryfall set code or null", "collector_number": "collector number or null", "printed_name": "card name as printed on the card if non-English, or null", "lang": "2-letter language code (en, ja, zhs, zht, de, fr, it, es, pt, ko, ru) or null"}
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

            guard let httpResponse = response as? HTTPURLResponse else {
                Self.lastError = "No response from Gemini"
                return nil
            }
            if httpResponse.statusCode == 429 {
                Self.markRateLimited()
                Self.lastError = "Rate limited — waiting 60s before retrying"
                print("[Gemini] Rate limited (429)")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                Self.lastError = "HTTP \(httpResponse.statusCode)"
                print("[Gemini] HTTP error: \(httpResponse.statusCode)")
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
            let printedName = result["printed_name"] as? String
            let lang = result["lang"] as? String

            Self.lastError = nil
            let langLabel = lang != nil && lang != "en" ? " lang=\(lang!)" : ""
            print("[Gemini] Identified: \(cardName) [\(setCode ?? "?")] #\(collectorNumber ?? "?")\(langLabel)")
            return GeminiCardResult(
                cardName: cardName,
                setCode: setCode,
                collectorNumber: collectorNumber,
                quantity: 1,
                boundingBox: nil,
                printedName: printedName,
                lang: lang
            )
        } catch {
            print("[Gemini] Request failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Identifies ALL cards in a full binder page photo. Returns an array of results.
    /// Uses a single API call instead of one per card.
    func identifyAllCards(image: CGImage) async -> (analysis: String?, cards: [GeminiCardResult])? {
        guard let apiKey = Self.apiKey, !apiKey.isEmpty else { return nil }
        Self.recordUsage()

        var uiImage = UIImage(cgImage: image)
        // Downscale very large images to keep payload reasonable
        let maxDimension: CGFloat = 2048
        if uiImage.size.width > maxDimension || uiImage.size.height > maxDimension {
            let scale = maxDimension / max(uiImage.size.width, uiImage.size.height)
            let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            uiImage = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: newSize)) }
            print("[Gemini] Downscaled image to \(Int(newSize.width))x\(Int(newSize.height))")
        }
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else { return nil }
        let base64 = jpegData.base64EncodedString()
        print("[Gemini] Payload size: \(jpegData.count / 1024)KB")

        guard let url = URL(string: "\(Self.endpoint)?key=\(apiKey)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let prompt = """
        List down all the Magic: The Gathering cards visible in this photo, their expansions, and number of pieces per card.
        Group identical cards together with a quantity count.
        For each unique card, determine the exact English card name and the Scryfall 3-letter set code based on the card's appearance (frame style, art, set symbol).
        Also estimate a bounding box for one representative copy as fractional coordinates (0.0-1.0) relative to image width/height.
        Include a brief analysis of what deck/archetype this appears to be.

        Return ONLY a JSON object (no other text or markdown):
        {"analysis": "Brief description of the deck archetype and format", "cards": [{"card_name": "exact name", "set_code": "abc", "quantity": 4, "x": 0.0, "y": 0.0, "w": 0.25, "h": 0.33}, ...]}
        Order cards by: creatures first, then spells, then lands. Include sideboard cards if visible.
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

            guard let httpResponse = response as? HTTPURLResponse else {
                Self.lastError = "No response from Gemini"
                return nil
            }
            if httpResponse.statusCode == 429 {
                Self.markRateLimited()
                Self.lastError = "Rate limited — waiting 60s before retrying"
                print("[Gemini] Batch: rate limited (429)")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                Self.lastError = "HTTP \(httpResponse.statusCode)"
                print("[Gemini] Batch HTTP error: \(httpResponse.statusCode)")
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

            print("[Gemini] Raw response (\(text.count) chars): \(text.prefix(500))")

            let cleaned = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let resultData = cleaned.data(using: .utf8) else {
                print("[Gemini] Batch: failed to encode cleaned text")
                return nil
            }
            guard let parsed = try? JSONSerialization.jsonObject(with: resultData) else {
                print("[Gemini] Batch: failed to parse JSON from: \(cleaned.prefix(300))")
                Self.lastError = "Failed to parse Gemini response as JSON"
                return nil
            }

            // Handle both object format {"analysis":..., "cards":[...]} and plain array [...]
            let array: [[String: Any]]
            var analysis: String?
            if let obj = parsed as? [String: Any] {
                array = obj["cards"] as? [[String: Any]] ?? []
                analysis = obj["analysis"] as? String
                print("[Gemini] Parsed object: analysis=\(analysis != nil), cards=\(array.count)")
            } else if let arr = parsed as? [[String: Any]] {
                array = arr
                print("[Gemini] Parsed plain array: \(array.count) items")
            } else {
                print("[Gemini] Batch: unexpected JSON structure: \(type(of: parsed))")
                Self.lastError = "Unexpected Gemini response format"
                return nil
            }

            let results = array.compactMap { item -> GeminiCardResult? in
                // Handle both "card_name" and "name" field names
                guard let name = (item["card_name"] as? String) ?? (item["name"] as? String) else {
                    print("[Gemini] Skipping item with no card_name/name: \(item.keys.sorted())")
                    return nil
                }
                var bbox: (x: Double, y: Double, w: Double, h: Double)?
                if let x = item["x"] as? Double,
                   let y = item["y"] as? Double,
                   let w = item["w"] as? Double,
                   let h = item["h"] as? Double,
                   w > 0 && h > 0 {
                    bbox = (x: x, y: y, w: w, h: h)
                }
                let qty = item["quantity"] as? Int ?? 1
                return GeminiCardResult(
                    cardName: name,
                    setCode: item["set_code"] as? String,
                    collectorNumber: item["collector_number"] as? String,
                    quantity: qty,
                    boundingBox: bbox
                )
            }

            Self.lastError = nil
            print("[Gemini] Batch: identified \(results.count) cards\(analysis.map { " — \($0)" } ?? "")")
            return (analysis: analysis, cards: results)
        } catch {
            Self.lastError = "Request failed: \(error.localizedDescription)"
            print("[Gemini] Batch request failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Text-Only Insight Generation

    /// Text-only insight uses the same model as the scanner so the
    /// user's API key always works (gemini-3-flash-preview handles both
    /// text and vision prompts).
    private static let textEndpoint = endpoint

    /// Generates a card insight using Gemini text model (no image).
    /// Uses 1 daily request. Returns the insight text or nil on failure.
    static func generateInsight(prompt: String) async -> String? {
        guard let apiKey = apiKey, !apiKey.isEmpty else { return nil }
        guard !isDailyLimitReached else { return nil }
        recordUsage()

        guard let url = URL(string: "\(textEndpoint)?key=\(apiKey)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "generationConfig": ["maxOutputTokens": 600],
            "contents": [[
                "parts": [["text": prompt]]
            ]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                markRateLimited()
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                return nil
            }
            lastError = nil
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastError = "Insight request failed: \(error.localizedDescription)"
            return nil
        }
    }
}

struct GeminiCardResult {
    let cardName: String
    let setCode: String?
    let collectorNumber: String?
    let quantity: Int
    /// Bounding box as fractional coordinates (0-1) relative to image dimensions.
    /// (x, y) is top-left corner; (w, h) is width and height.
    let boundingBox: (x: Double, y: Double, w: Double, h: Double)?
    /// Localized card name as printed (e.g. Japanese name). Nil for English cards.
    let printedName: String?
    /// Language code (e.g. "ja", "zhs"). Nil for English.
    let lang: String?

    init(cardName: String, setCode: String?, collectorNumber: String?,
         quantity: Int, boundingBox: (x: Double, y: Double, w: Double, h: Double)?,
         printedName: String? = nil, lang: String? = nil) {
        self.cardName = cardName
        self.setCode = setCode
        self.collectorNumber = collectorNumber
        self.quantity = quantity
        self.boundingBox = boundingBox
        self.printedName = printedName
        self.lang = lang
    }
}
