import SwiftUI

/// AI-generated card insight section. Shows buy/sell/hold analysis
/// with tappable budget alternatives. Persists to DB.
struct CardInsightView: View {

    let card: Card
    let cardRepository: CardRepositoryProtocol

    @State private var insight: String?
    @State private var insightDate: String?
    @State private var budgetAlternatives: [(name: String, reason: String)] = []
    @State private var gameplayAlternatives: [(name: String, reason: String)] = []
    @State private var resolvedAlternatives: [String: Card] = [:]
    @State private var isGenerating: Bool = false
    @State private var error: String?
    @State private var showFullInsight: Bool = false
    @State private var usedKeyLabel: String?

    private var isConfigured: Bool { GeminiVisionService.isConfigured }
    private var remainingQuota: Int { max(0, 1000 - GeminiVisionService.shared.dailyUsageSync) }

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
                        .lineLimit(6)
                    Button {
                        showFullInsight = true
                    } label: {
                        Text("Read more")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MD3Theme.primary)
                    }
                    .buttonStyle(.plain)

                    // Budget alternatives
                    if !budgetAlternatives.isEmpty {
                        Divider()
                        Text("Budget Alternatives")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        ForEach(budgetAlternatives, id: \.name) { alt in
                            alternativeRow(alt)
                        }
                    }
                    // Gameplay alternatives
                    if !gameplayAlternatives.isEmpty {
                        Divider()
                        Text("Gameplay Alternatives")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        ForEach(gameplayAlternatives, id: \.name) { alt in
                            alternativeRow(alt)
                        }
                    }
                } else if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Generating insight…")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                    if let usedKeyLabel {
                        Text("Using \(usedKeyLabel) key")
                            .font(.system(size: 9))
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
        .sheet(isPresented: $showFullInsight) {
            insightFullScreen
        }
        .task(id: card.scryfallID) {
            // Reset state when card changes (e.g. navigating Other Printings)
            insight = nil
            insightDate = nil
            budgetAlternatives = []
            gameplayAlternatives = []
            resolvedAlternatives = [:]
            error = nil
            await loadCachedInsight()
        }
        .onAppear {
            // Reload from DB on re-appear (e.g. returning from alternative)
            Task { await loadFromDB() }
        }
    }

    // MARK: - Full Screen Insight

    private var insightFullScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let insight {
                        Text(insight)
                            .font(.body)
                            .foregroundStyle(MD3Theme.onSurface)
                            .textSelection(.enabled)
                    }

                    if !budgetAlternatives.isEmpty {
                        Divider()
                        Text("Budget Alternatives")
                            .font(.headline)
                            .foregroundStyle(MD3Theme.onSurface)
                        ForEach(budgetAlternatives, id: \.name) { alt in
                            alternativeRow(alt)
                        }
                    }

                    if !gameplayAlternatives.isEmpty {
                        Divider()
                        Text("Gameplay Alternatives")
                            .font(.headline)
                            .foregroundStyle(MD3Theme.onSurface)
                        ForEach(gameplayAlternatives, id: \.name) { alt in
                            alternativeRow(alt)
                        }
                    }
                }
                .padding(20)
            }
            .background(MD3Theme.background)
            .navigationTitle("AI Insight — \(card.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFullInsight = false }
                }
            }
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
        // Always load from DB for the freshest data
        await loadFromDB()
        // Fall back to card struct if DB returned nothing
        if insight == nil, let cached = card.insight {
            parseInsight(cached)
            insightDate = card.insightDate
        }
    }

    /// Loads insight directly from DB, bypassing the stale Card struct.
    private func loadFromDB() async {
        guard let repo = cardRepository as? LocalCardRepository,
              let record = try? await repo.databaseManager.findCard(scryfallID: card.scryfallID) else { return }
        let fresh = record.toDomain()
        if let dbInsight = fresh.insight {
            parseInsight(dbInsight)
            insightDate = fresh.insightDate
        }
    }

    /// Parses stored insight text. The format is:
    /// `[RECOMMENDATION] analysis text\n---ALT---\nname1|||reason1\nname2|||reason2`
    /// Parses stored insight. Format:
    /// `analysis\n---BUDGET---\nname|||reason\n---GAMEPLAY---\nname|||reason`
    private func parseInsight(_ stored: String) {
        budgetAlternatives = []
        gameplayAlternatives = []

        let budgetSplit = stored.components(separatedBy: "\n---BUDGET---\n")
        if budgetSplit.count > 1 {
            insight = budgetSplit[0]
            let rest = budgetSplit[1]
            let gameplaySplit = rest.components(separatedBy: "\n---GAMEPLAY---\n")
            budgetAlternatives = parseAltLines(gameplaySplit[0])
            if gameplaySplit.count > 1 {
                gameplayAlternatives = parseAltLines(gameplaySplit[1])
            }
            return
        }

        // Legacy format (old ---ALT--- separator)
        let legacySplit = stored.components(separatedBy: "\n---ALT---\n")
        insight = legacySplit[0] // Strip the ---ALT--- portion
        if legacySplit.count > 1 {
            budgetAlternatives = parseAltLines(legacySplit[1])
        }
    }

    private func parseAltLines(_ text: String) -> [(name: String, reason: String)] {
        text.components(separatedBy: "\n").compactMap { line in
            let fields = line.components(separatedBy: "|||")
            guard fields.count == 2, !fields[0].isEmpty else { return nil }
            return (name: fields[0], reason: fields[1])
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

        let formatInfo = card.legalities.detailedSummary

        let prompt = """
        MTG card analysis. Return ONLY JSON, no markdown wrapping.
        Card: \(card.name) | Set: \(card.set.name) | \(card.rarity.rawValue) | \(card.typeLine) | \(priceInfo)
        CURRENT format status (trust this, not your training data): \(formatInfo)
        {"recommendation":"BUY/SELL/HOLD","analysis":"150-200 word analysis with these sections separated by newlines:\n\n**Competitive Playability:** which formats and archetypes use this card, how many copies typically played\n\n**Price Outlook:** price direction, reprint risk, supply factors for this \(card.set.name) printing\n\n**Collectibility:** alt arts, foil premium, reserved list, special printings\n\nUse the CURRENT format status above, not outdated info.","budget_alternatives":[{"name":"exact Scryfall card name","reason":"10 word reason"}],"gameplay_alternatives":[{"name":"exact Scryfall card name","reason":"10 word reason"}]}
        budget_alternatives: 2-3 cheaper cards that do a similar job. gameplay_alternatives: 2-3 cards at any price that are the best strategic substitutes or upgrades. All must be legal in the same formats. Use exact Scryfall English names.
        """

        usedKeyLabel = GeminiVisionService.shared.isUsingAltKeySync ? "alt" : "primary"
        guard let result = await GeminiVisionService.shared.generateInsight(prompt: prompt) else {
            error = "Failed to generate insight. Check Gemini settings."
            return
        }
        usedKeyLabel = await GeminiVisionService.shared.lastUsedKey

        // Parse JSON response
        let cleaned = result
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var analysisText: String
        var budget: [(name: String, reason: String)] = []
        var gameplay: [(name: String, reason: String)] = []

        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let rec = json["recommendation"] as? String ?? "HOLD"
            let analysis = json["analysis"] as? String ?? cleaned
            analysisText = "[\(rec)] \(analysis)"
            budget = (json["budget_alternatives"] as? [[String: String]] ?? []).compactMap { dict in
                guard let name = dict["name"], let reason = dict["reason"] else { return nil }
                return (name: name, reason: reason)
            }
            gameplay = (json["gameplay_alternatives"] as? [[String: String]] ?? []).compactMap { dict in
                guard let name = dict["name"], let reason = dict["reason"] else { return nil }
                return (name: name, reason: reason)
            }
            // Fallback: old "alternatives" key
            if budget.isEmpty && gameplay.isEmpty {
                let alts = (json["alternatives"] as? [[String: String]] ?? []).compactMap { dict -> (name: String, reason: String)? in
                    guard let name = dict["name"], let reason = dict["reason"] else { return nil }
                    return (name: name, reason: reason)
                }
                budget = alts
            }
        } else {
            // JSON parsing failed (likely truncated response) — retry hint
            error = "AI response was incomplete. Tap refresh to try again."
            return
        }

        insight = analysisText
        budgetAlternatives = budget
        gameplayAlternatives = gameplay
        let dateStr = Self.dateFormatter.string(from: Date())
        insightDate = dateStr

        // Serialize for DB
        var storedText = analysisText
        if !budget.isEmpty {
            let lines = budget.map { "\($0.name)|||\($0.reason)" }
            storedText += "\n---BUDGET---\n" + lines.joined(separator: "\n")
        }
        if !gameplay.isEmpty {
            let lines = gameplay.map { "\($0.name)|||\($0.reason)" }
            storedText += "\n---GAMEPLAY---\n" + lines.joined(separator: "\n")
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
