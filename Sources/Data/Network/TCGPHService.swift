import Foundation

// MARK: - Models

struct TCGPHListing: Identifiable, Sendable {
    let id = UUID()
    let storeName: String
    let price: Double       // in PHP
    let quantity: Int
    let condition: String   // "NM", "LP", "Un."
    let storeURL: String    // direct link to buy
}

struct TCGPHResult: Sendable {
    let cardName: String
    let setName: String
    let listings: [TCGPHListing]
    let tcgphURL: String    // link to tcgph.com page
}

// MARK: - Service

/// Fetches Philippine store listings from tcgph.com by scraping HTML.
/// Uses a specific-printing URL first, then falls back to the card
/// overview slug. Results are cached in-session per set+collector pair.
actor TCGPHService {
    static let shared = TCGPHService()

    private var cache: [String: TCGPHResult] = [:]

    /// Fetches store listings for a specific card printing.
    /// Tries: 1) /cards/{set}/{num}/en/n  2) /card/{slug}  3) JSON-LD from meta
    func fetchListings(setCode: String, collectorNumber: String, cardName: String) async -> TCGPHResult? {
        let cacheKey = "\(setCode)-\(collectorNumber)"
        if let cached = cache[cacheKey] { return cached }

        // Try specific printing URL (nonfoil, then foil)
        let setLower = setCode.lowercased()
        for finish in ["n", "f"] {
            let url = "https://tcgph.com/cards/\(setLower)/\(collectorNumber)/en/\(finish)"
            if let result = await fetchAndParse(url: url, cardName: cardName) {
                cache[cacheKey] = result
                return result
            }
        }

        // Fallback to card overview (shows all printings with listings)
        let slug = cardName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let fallbackURL = "https://tcgph.com/card/\(slug)"
        if let result = await fetchAndParse(url: fallbackURL, cardName: cardName) {
            cache[cacheKey] = result
            return result
        }

        return nil
    }

    private func fetchAndParse(url urlString: String, cardName: String) async -> TCGPHResult? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        let listings = parseListings(from: html)
        guard !listings.isEmpty else { return nil }
        return TCGPHResult(
            cardName: cardName,
            setName: "",
            listings: listings,
            tcgphURL: urlString
        )
    }

    // MARK: - HTML Parsing

    /// Parses store listings from the HTML.
    /// Strategy 1: listing-row divs on /cards/{set}/{num} pages
    /// Strategy 2: data-ga-* attributes on /card/{slug} hub pages
    private func parseListings(from html: String) -> [TCGPHListing] {
        var listings: [TCGPHListing] = []
        let nsHTML = html as NSString

        // Strategy 1: Parse listing rows on specific-printing pages.
        // Each row: <div id="listing-row-listing-..." data-href="STORE_URL">
        //   First <a> text = store name, ₱NNN = price, Nx = quantity
        let rowPattern = #"id="listing-row-listing-[^"]*"[^>]*data-href="([^"]*)"#
        if let rowRegex = try? NSRegularExpression(pattern: rowPattern) {
            let rowMatches = rowRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
            for rowMatch in rowMatches {
                guard rowMatch.numberOfRanges > 1 else { continue }
                let storeURL = nsHTML.substring(with: rowMatch.range(at: 1))
                    .replacingOccurrences(of: "&amp;", with: "&")

                let startIdx = rowMatch.range.location
                let endIdx = min(startIdx + 2000, nsHTML.length)
                let context = nsHTML.substring(with: NSRange(location: startIdx, length: endIdx - startIdx))

                let storeName = extractStoreName(from: context)
                let price = extractPrice(from: context)
                let quantity = extractQuantity(from: context)
                let condition = extractCondition(from: context)

                if !storeName.isEmpty && price > 0 {
                    listings.append(TCGPHListing(
                        storeName: storeName,
                        price: price,
                        quantity: quantity,
                        condition: condition,
                        storeURL: storeURL
                    ))
                }
            }
        }

        // Strategy 2: Parse data-ga-* links on card hub pages (/card/{slug}).
        // Format: <a href="..." ... data-ga-store="Store" data-ga-price="11000" ...>₱110</a>
        // Attributes appear in any order within the <a> tag.
        if listings.isEmpty {
            let gaLinkPattern = #"<a\s[^>]*data-ga-store="([^"]*)"[^>]*data-ga-price="(\d+)"[^>]*href="([^"]*)"[^>]*>"#
            let gaLinkAltPattern = #"<a\s[^>]*href="([^"]*)"[^>]*data-ga-store="([^"]*)"[^>]*data-ga-price="(\d+)"[^>]*>"#

            for (pattern, storeIdx, priceIdx, hrefIdx) in [
                (gaLinkPattern, 1, 2, 3),
                (gaLinkAltPattern, 2, 3, 1)
            ] {
                guard listings.isEmpty,
                      let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
                for m in matches where m.numberOfRanges > 3 {
                    let store = nsHTML.substring(with: m.range(at: storeIdx))
                    let priceStr = nsHTML.substring(with: m.range(at: priceIdx))
                    let href = nsHTML.substring(with: m.range(at: hrefIdx))
                        .replacingOccurrences(of: "&amp;", with: "&")
                    // data-ga-price is in centavos (e.g. 11000 = ₱110)
                    let pricePHP = (Double(priceStr) ?? 0) / 100.0

                    // Extract condition from surrounding context
                    let mStart = m.range.location
                    let ctxStart = max(0, mStart - 200)
                    let ctxEnd = min(mStart + 200, nsHTML.length)
                    let ctx = nsHTML.substring(with: NSRange(location: ctxStart, length: ctxEnd - ctxStart))
                    let condition = extractCondition(from: ctx)

                    // Extract quantity from surrounding context
                    let quantity = extractQuantity(from: ctx)

                    if pricePHP > 0 {
                        listings.append(TCGPHListing(
                            storeName: store,
                            price: pricePHP,
                            quantity: quantity,
                            condition: condition,
                            storeURL: href.hasPrefix("http") ? href : "https://tcgph.com\(href)"
                        ))
                    }
                }
            }
        }

        // Strategy 3: Parse JSON-LD structured data as last resort.
        // The page embeds schema.org Product with AggregateOffer.
        if listings.isEmpty {
            if let lowestPrice = extractJSONLDPrice(from: html) {
                listings.append(TCGPHListing(
                    storeName: extractJSONLDStoreName(from: html) ?? "TCGph",
                    price: lowestPrice,
                    quantity: 1,
                    condition: "NM",
                    storeURL: ""
                ))
            }
        }

        return listings.sorted { $0.price < $1.price }
    }

    /// Extracts store name from a listing row context.
    /// The first <a> tag inside the row whose text is NOT a price is the store.
    private func extractStoreName(from context: String) -> String {
        // Try /stores/ link first (some pages use it)
        let storesPattern = #"href="/stores/[^"]*"[^>]*>([^<]+)</a>"#
        if let regex = try? NSRegularExpression(pattern: storesPattern),
           let match = regex.firstMatch(in: context, range: NSRange(location: 0, length: (context as NSString).length)),
           match.numberOfRanges > 1 {
            let name = (context as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }

        // Fallback: first <a> tag text that looks like a store name
        // (not a price, not empty, at least 2 chars)
        let linkPattern = #"<a\s[^>]*>([^<]+)</a>"#
        if let regex = try? NSRegularExpression(pattern: linkPattern) {
            let matches = regex.matches(in: context, range: NSRange(location: 0, length: (context as NSString).length))
            for m in matches where m.numberOfRanges > 1 {
                let text = (context as NSString).substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Skip prices, empty strings, single chars
                if text.count >= 2 && !text.hasPrefix("₱") && !text.contains("Leave") {
                    return text
                }
            }
        }
        return ""
    }

    private func extractPrice(from context: String) -> Double {
        let pattern = #"₱([\d,]+(?:\.\d{2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: context, range: NSRange(location: 0, length: (context as NSString).length)),
              match.numberOfRanges > 1 else { return 0 }
        let priceStr = (context as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
        return Double(priceStr) ?? 0
    }

    private func extractQuantity(from context: String) -> Int {
        // Match "Nx" quantity patterns (e.g. "9x", "1x")
        let pattern = #"(\d+)x"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: context, range: NSRange(location: 0, length: (context as NSString).length)),
              match.numberOfRanges > 1 else { return 1 }
        return Int((context as NSString).substring(with: match.range(at: 1))) ?? 1
    }

    private func extractCondition(from context: String) -> String {
        // Check full condition names first, then abbreviations
        for cond in ["NM", "LP", "MP", "HP", "DMG", "Un."] {
            if context.contains(cond) { return cond }
        }
        // Single-letter condition codes used by tcgph in listing rows
        // (e.g. "U" for Unspecified) — check inside condition spans
        let condPattern = #"whitespace-nowrap">\s*([A-Z])\s*</span>"#
        if let regex = try? NSRegularExpression(pattern: condPattern),
           let match = regex.firstMatch(in: context, range: NSRange(location: 0, length: (context as NSString).length)),
           match.numberOfRanges > 1 {
            let code = (context as NSString).substring(with: match.range(at: 1))
            switch code {
            case "N": return "NM"
            case "L": return "LP"
            case "M": return "MP"
            case "H": return "HP"
            case "D": return "DMG"
            case "U": return "Un."
            default: return code
            }
        }
        return "NM"
    }

    // MARK: - JSON-LD Parsing

    /// Extracts the lowest price from JSON-LD Product structured data.
    private func extractJSONLDPrice(from html: String) -> Double? {
        let pattern = #""lowPrice"\s*:\s*([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        return Double((html as NSString).substring(with: match.range(at: 1)))
    }

    /// Extracts a store name from the meta description (e.g. "From ₱60 at Jace Collection").
    private func extractJSONLDStoreName(from html: String) -> String? {
        let pattern = #"at\s+([A-Z][^".]+?)[\."<]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        return (html as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }
}
