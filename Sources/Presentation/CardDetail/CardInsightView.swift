import SwiftUI

/// AI-generated card insight section. Shows buy/sell/hold analysis
/// with tappable budget alternatives. Persists to DB.
struct CardInsightView: View {

    let card: Card
    let cardRepository: CardRepositoryProtocol

    @State private var insight: String?
    @State private var insightDate: String?
    @State private var alternatives: [(name: String, reason: String)] = []
    @State private var resolvedAlternatives: [String: Card] = [:]
    @State private var isGenerating: Bool = false
    @State private var error: String?

    private var isConfigured: Bool { GeminiVisionService.isConfigured }
    private var remainingQuota: Int { max(0, 1000 - GeminiVisionService.dailyUsage) }

    var body: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text("AI Insight")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                    Spacer()
                    if let insightDate {
                        Text(insightDate)
                            .font(.system(size: 9))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                    if insight != nil {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button {
                                Task { await generateInsight() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(MD3Theme.primary)
                            }
                            .disabled(!isConfigured)
                        }
                    }
                }

                // Content
                if let insight {
                    Text(insight)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurface)
                        .textSelection(.enabled)

                    // Tappable alternatives
                    if !alternatives.isEmpty {
                        Divider()
                        Text("Budget Alternatives")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)

                        ForEach(alternatives, id: \.name) { alt in
                            alternativeRow(alt)
                        }
                    }
                } else if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Generating insight...")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                } else if !isConfigured {
                    Text("Set up Gemini API key in Settings to enable AI insights")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                } else {
                    Button {
                        Task { await generateInsight() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Generate Insight")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Text("\(remainingQuota) Gemini requests remaining today")
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
        .task(id: card.scryfallID) {
            // Reset state when card changes (e.g. navigating Other Printings)
            insight = nil
            insightDate = nil
            alternatives = []
            resolvedAlternatives = [:]
            error = nil
            await loadCachedInsight()
        }
    }

    // MARK: - Alternative Row

    @ViewBuilder
    private func alternativeRow(_ alt: (name: String, reason: String)) -> some View {
        let rowContent = HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(alt.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                Text(alt.reason)
                    .font(.system(size: 10))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(2)
            }
            Spacer()
            if resolvedAlternatives[alt.name] != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
            }
        }
        .padding(.vertical, 2)
        .task { await resolveAlternative(name: alt.name) }

        if let altCard = resolvedAlternatives[alt.name] {
            NavigationLink {
                CardDetailView(
                    card: altCard,
                    repository: cardRepository,
                    deckRepository: nil,
                    onScanAnother: {}
                )
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private func resolveAlternative(name: String) async {
        guard resolvedAlternatives[name] == nil else { return }
        let resolver = CardResolver(cardRepository: cardRepository)
        if let card = await resolver.resolve(name: name, strategy: .cheapest) {
            resolvedAlternatives[name] = card
        }
    }

    // MARK: - Load Cached Insight

    private func loadCachedInsight() async {
        // Try from passed card first
        if let cached = card.insight {
            parseInsight(cached)
            insightDate = card.insightDate
            return
        }
        // Reload from DB (card struct may be stale)
        if let repo = cardRepository as? LocalCardRepository,
           let record = try? await repo.databaseManager.findCard(scryfallID: card.scryfallID) {
            let fresh = record.toDomain()
            if let dbInsight = fresh.insight {
                parseInsight(dbInsight)
                insightDate = fresh.insightDate
            }
        }
    }

    /// Parses stored insight text. The format is:
    /// `[RECOMMENDATION] analysis text\n---ALT---\nname1|||reason1\nname2|||reason2`
    private func parseInsight(_ stored: String) {
        let parts = stored.components(separatedBy: "\n---ALT---\n")
        insight = parts[0]
        if parts.count > 1 {
            alternatives = parts[1].components(separatedBy: "\n").compactMap { line in
                let fields = line.components(separatedBy: "|||")
                guard fields.count == 2 else { return nil }
                return (name: fields[0], reason: fields[1])
            }
        }
    }

    // MARK: - Generate Insight

    private func generateInsight() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }

        let priceInfo: String
        if let usd = card.prices.usd {
            priceInfo = "Current price: $\(usd) USD"
        } else if let foil = card.prices.usdFoil {
            priceInfo = "Current foil price: $\(foil) USD"
        } else {
            priceInfo = "No current price data"
        }

        let formatInfo = card.legalities.summary

        let prompt = """
        You are an MTG finance and competitive play analyst. Analyze this Magic: The Gathering card.

        Card: \(card.name)
        Set: \(card.set.name) (\(card.set.code.uppercased()))
        Rarity: \(card.rarity.rawValue)
        Type: \(card.typeLine)
        \(priceInfo)
        Format legality: \(formatInfo)

        Return ONLY a JSON object (no markdown, no other text):
        {"recommendation":"BUY or SELL or HOLD","analysis":"Detailed analysis (200-250 words) structured as: **Recommendation: BUY/SELL/HOLD** then paragraphs on **Competitive Playability** (formats, archetypes, how many copies typically played), **Price Outlook** (direction, reasoning, reprint risk, supply factors), and **Collectibility** (alt arts, foil premium, reserved list status, special printings). Use markdown bold for section headers.","alternatives":[{"name":"exact card name","reason":"why it substitutes (max 20 words)"}]}

        For alternatives: suggest 2-3 cheaper cards that fill a similar role. They MUST be legal in at least one of the same formats as \(card.name). Use exact English card names as they appear on Scryfall. Include the specific printing/set context in the analysis since this is the \(card.set.name) version.
        """

        guard let result = await GeminiVisionService.generateInsight(prompt: prompt) else {
            error = "Failed to generate insight. Check Gemini settings."
            return
        }

        // Parse JSON response
        let cleaned = result
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var analysisText: String
        var alts: [(name: String, reason: String)] = []

        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let rec = json["recommendation"] as? String ?? "HOLD"
            let analysis = json["analysis"] as? String ?? cleaned
            analysisText = "[\(rec)] \(analysis)"
            let altArray = json["alternatives"] as? [[String: String]] ?? []
            alts = altArray.compactMap { dict in
                guard let name = dict["name"], let reason = dict["reason"] else { return nil }
                return (name: name, reason: reason)
            }
        } else {
            // Fallback: use raw text
            analysisText = cleaned
        }

        insight = analysisText
        alternatives = alts
        let dateStr = Self.dateFormatter.string(from: Date())
        insightDate = dateStr

        // Serialize for DB: analysis + alternatives in a parseable format
        var storedText = analysisText
        if !alts.isEmpty {
            let altLines = alts.map { "\($0.name)|||\($0.reason)" }
            storedText += "\n---ALT---\n" + altLines.joined(separator: "\n")
        }

        // Save to DB
        if let repo = cardRepository as? LocalCardRepository {
            try? await repo.databaseManager.saveInsight(
                scryfallID: card.scryfallID,
                insight: storedText,
                date: dateStr
            )
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
