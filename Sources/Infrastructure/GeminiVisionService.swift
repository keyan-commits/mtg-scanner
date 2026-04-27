import Foundation
import CoreGraphics
import UIKit

/// Identifies Magic: The Gathering cards using Google's Gemini Vision API.
/// Used as a fallback when the local pipeline (OCR + visual search) fails.
/// Free tier: 15 requests/minute, 1,500/day.
actor GeminiVisionService {

    static let shared = GeminiVisionService()

    // MARK: - Static Configuration (UserDefaults-backed, thread-safe)

    private static let apiKeyKey = "geminiAPIKey"
    private static let altApiKeyKey = "geminiAltAPIKey"
    // Gemini 3 Flash Preview: 15 RPM, 1000 RPD free tier
    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent"

    static var apiKey: String? {
        get { UserDefaults.standard.string(forKey: apiKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }

    /// Alternative API key — used as fallback when the primary key is rate-limited.
    static var altApiKey: String? {
        get { UserDefaults.standard.string(forKey: altApiKeyKey) }
        set { UserDefaults.standard.set(newValue, forKey: altApiKeyKey) }
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

    /// Tracks which key to try first (persists across calls).
    /// Starts with "primary", swaps to "alt" on failure, and back.
    private static let preferredKeyKey = "geminiPreferredKey"
    static var preferredKey: String {
        get { UserDefaults.standard.string(forKey: preferredKeyKey) ?? "primary" }
        set { UserDefaults.standard.set(newValue, forKey: preferredKeyKey) }
    }

    // MARK: - Instance Runtime State

    private let dailyLimitKey = "geminiDailyCount"
    private let dailyDateKey = "geminiDailyDate"
    private let altDailyLimitKey = "geminiAltDailyCount"
    private let altDailyDateKey = "geminiAltDailyDate"
    // Gemini 3 Flash Preview free tier: 15 RPM, 1000 RPD
    private let dailyLimit = 1000

    /// Which key was used for the last insight call.
    var lastUsedKey: String = "primary"

    /// Returns the best available API key (primary, or alt if primary is rate-limited/exhausted).
    var activeApiKey: String? {
        let primaryOK = !isRateLimited && !isDailyLimitReached
        if primaryOK, let key = Self.apiKey, !key.isEmpty { return key }
        if !isAltDailyLimitReached, let alt = Self.altApiKey, !alt.isEmpty { return alt }
        if let key = Self.apiKey, !key.isEmpty { return key }
        return nil
    }

    /// Whether the active key is the alt key.
    var isUsingAltKey: Bool {
        let primaryOK = !isRateLimited && !isDailyLimitReached
        if primaryOK, let key = Self.apiKey, !key.isEmpty { return false }
        if let alt = Self.altApiKey, !alt.isEmpty { return true }
        return false
    }

    /// Whether Gemini should be used right now (configured + enabled + within limit + not rate-limited).
    var isActive: Bool {
        Self.isConfigured && Self.isEnabled && !isDailyLimitReached && !isRateLimited
    }

    /// Last error message from Gemini (shown to user).
    var lastError: String? {
        get { UserDefaults.standard.string(forKey: "geminiLastError") }
        set { UserDefaults.standard.set(newValue, forKey: "geminiLastError") }
    }

    /// Whether Gemini hit a rate limit (429) — auto-resets after 60 seconds.
    private var isRateLimited: Bool {
        let rateLimitedAt = UserDefaults.standard.double(forKey: "geminiRateLimitedAt")
        guard rateLimitedAt > 0 else { return false }
        return Date().timeIntervalSince1970 - rateLimitedAt < 60
    }

    private func markRateLimited() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "geminiRateLimitedAt")
    }

    // MARK: - Daily Usage Tracking

    /// Number of Gemini requests made today.
    var dailyUsage: Int {
        resetIfNewDay()
        return UserDefaults.standard.integer(forKey: dailyLimitKey)
    }

    /// Whether the daily free-tier limit has been reached.
    var isDailyLimitReached: Bool {
        dailyUsage >= dailyLimit
    }

    /// Manually sets the daily usage count (for syncing with Google's dashboard).
    func setDailyUsage(_ count: Int) {
        resetIfNewDay()
        UserDefaults.standard.set(count, forKey: dailyLimitKey)
    }

    /// Records one API usage for the currently active key.
    func recordUsage() {
        resetIfNewDay()
        if isUsingAltKey {
            recordAltUsage()
        } else {
            let count = UserDefaults.standard.integer(forKey: dailyLimitKey)
            UserDefaults.standard.set(count + 1, forKey: dailyLimitKey)
        }
    }

    private func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let stored = UserDefaults.standard.double(forKey: dailyDateKey)
        if stored < today {
            UserDefaults.standard.set(0, forKey: dailyLimitKey)
            UserDefaults.standard.set(today, forKey: dailyDateKey)
        }
        let altStored = UserDefaults.standard.double(forKey: altDailyDateKey)
        if altStored < today {
            UserDefaults.standard.set(0, forKey: altDailyLimitKey)
            UserDefaults.standard.set(today, forKey: altDailyDateKey)
        }
    }

    // MARK: - Alt Key Usage

    var altDailyUsage: Int {
        resetIfNewDay()
        return UserDefaults.standard.integer(forKey: altDailyLimitKey)
    }

    var isAltDailyLimitReached: Bool {
        altDailyUsage >= dailyLimit
    }

    func recordAltUsage() {
        resetIfNewDay()
        let count = UserDefaults.standard.integer(forKey: altDailyLimitKey)
        UserDefaults.standard.set(count + 1, forKey: altDailyLimitKey)
    }

    func setAltDailyUsage(_ count: Int) {
        resetIfNewDay()
        UserDefaults.standard.set(count, forKey: altDailyLimitKey)
    }

    // MARK: - Nonisolated Accessors for Synchronous UI Access

    /// Synchronous accessors that read directly from UserDefaults (thread-safe).
    /// These allow SwiftUI views to read values without async/await.
    nonisolated var dailyUsageSync: Int {
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let stored = UserDefaults.standard.double(forKey: dailyDateKey)
        if stored < today { return 0 }
        return UserDefaults.standard.integer(forKey: dailyLimitKey)
    }

    nonisolated var altDailyUsageSync: Int {
        let today = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let stored = UserDefaults.standard.double(forKey: altDailyDateKey)
        if stored < today { return 0 }
        return UserDefaults.standard.integer(forKey: altDailyLimitKey)
    }

    nonisolated var isDailyLimitReachedSync: Bool {
        dailyUsageSync >= 1000
    }

    nonisolated var isAltDailyLimitReachedSync: Bool {
        altDailyUsageSync >= 1000
    }

    nonisolated var isActiveSync: Bool {
        Self.isConfigured && Self.isEnabled && !isDailyLimitReachedSync && !isRateLimitedSync
    }

    nonisolated var isUsingAltKeySync: Bool {
        let primaryOK = !isRateLimitedSync && !isDailyLimitReachedSync
        if primaryOK, let key = Self.apiKey, !key.isEmpty { return false }
        if let alt = Self.altApiKey, !alt.isEmpty { return true }
        return false
    }

    nonisolated var lastErrorSync: String? {
        UserDefaults.standard.string(forKey: "geminiLastError")
    }

    private nonisolated var isRateLimitedSync: Bool {
        let rateLimitedAt = UserDefaults.standard.double(forKey: "geminiRateLimitedAt")
        guard rateLimitedAt > 0 else { return false }
        return Date().timeIntervalSince1970 - rateLimitedAt < 60
    }

    /// Clears the last error (convenience for callers outside the actor).
    func clearLastError() {
        lastError = nil
    }

    // MARK: - Card Identification

    /// Identifies a card from a CGImage. Returns (cardName, setCode?, collectorNumber?) or nil.
    func identifyCard(image: CGImage) async -> GeminiCardResult? {
        guard let apiKey = activeApiKey else { return nil }
        recordUsage()

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
                lastError = "No response from Gemini"
                return nil
            }
            if httpResponse.statusCode == 429 {
                markRateLimited()
                lastError = "Rate limited — waiting 60s before retrying"
                print("[Gemini] Rate limited (429)")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                lastError = "HTTP \(httpResponse.statusCode)"
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

            lastError = nil
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
        guard let apiKey = activeApiKey else { return nil }
        recordUsage()

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
                lastError = "No response from Gemini"
                return nil
            }
            if httpResponse.statusCode == 429 {
                markRateLimited()
                lastError = "Rate limited — waiting 60s before retrying"
                print("[Gemini] Batch: rate limited (429)")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                lastError = "HTTP \(httpResponse.statusCode)"
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
                lastError = "Failed to parse Gemini response as JSON"
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
                lastError = "Unexpected Gemini response format"
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

            lastError = nil
            print("[Gemini] Batch: identified \(results.count) cards\(analysis.map { " — \($0)" } ?? "")")
            return (analysis: analysis, cards: results)
        } catch {
            lastError = "Request failed: \(error.localizedDescription)"
            print("[Gemini] Batch request failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Text-Only Insight Generation

    /// Text-only insight uses the same model as the scanner so the
    /// user's API key always works (gemini-3-flash-preview handles both
    /// text and vision prompts).
    private var textEndpoint: String { Self.endpoint }

    /// Generates a card insight using Gemini text model (no image).
    /// Uses the preferred key first. On rate limit/failure, swaps to
    /// the other key and retries. Loops between keys on errors.
    func generateInsight(prompt: String) async -> String? {
        var allKeys: [(key: String, label: String)] = []
        if let primary = Self.apiKey, !primary.isEmpty { allKeys.append((primary, "primary")) }
        if let alt = Self.altApiKey, !alt.isEmpty { allKeys.append((alt, "alt")) }
        guard !allKeys.isEmpty else { return nil }

        // Put preferred key first
        let sorted = allKeys.sorted { a, _ in a.label == Self.preferredKey }

        for (key, label) in sorted {
            if let result = await callGemini(prompt: prompt, apiKey: key) {
                lastUsedKey = label
                Self.preferredKey = label // Stick with working key
                if label == "primary" { recordUsage() }
                else { recordAltUsage() }
                return result
            }
            // This key failed — swap preference to the other
            Self.preferredKey = (label == "primary") ? "alt" : "primary"
            lastUsedKey = label + " (failed)"
        }
        return nil
    }

    private func callGemini(prompt: String, apiKey: String) async -> String? {
        guard let url = URL(string: "\(textEndpoint)?key=\(apiKey)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
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
                return nil // Will retry with next key
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
