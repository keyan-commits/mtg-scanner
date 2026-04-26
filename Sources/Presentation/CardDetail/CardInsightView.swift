import SwiftUI

/// AI-generated card insight section. Shows buy/sell/hold analysis
/// based on card data. Persists to DB so it only needs to be
/// generated once per card.
struct CardInsightView: View {

    let card: Card
    let cardRepository: CardRepositoryProtocol

    @State private var insight: String?
    @State private var insightDate: String?
    @State private var isGenerating: Bool = false
    @State private var error: String?

    private var isConfigured: Bool { GeminiVisionService.isConfigured }
    private var remainingQuota: Int { max(0, 1000 - GeminiVisionService.dailyUsage) }

    var body: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
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
                        Button {
                            Task { await generateInsight() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(MD3Theme.primary)
                        }
                        .disabled(isGenerating || !isConfigured)
                    }
                }

                if let insight {
                    Text(insight)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurface)
                        .textSelection(.enabled)
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
        .task {
            // Load from the passed card first
            if let cached = card.insight {
                insight = cached
                insightDate = card.insightDate
                return
            }
            // If nil, reload from DB (the card struct may be stale)
            if let repo = cardRepository as? LocalCardRepository,
               let record = try? await repo.databaseManager.findCard(scryfallID: card.scryfallID) {
                let fresh = record.toDomain()
                if let dbInsight = fresh.insight {
                    insight = dbInsight
                    insightDate = fresh.insightDate
                }
            }
        }
    }

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
        You are an MTG finance and competitive play analyst. Analyze this Magic: The Gathering card for a player who buys and sells cards competitively.

        Card: \(card.name)
        Set: \(card.set.name) (\(card.set.code.uppercased()))
        Rarity: \(card.rarity.rawValue)
        Type: \(card.typeLine)
        \(priceInfo)
        Format legality: \(formatInfo)

        Provide a concise analysis (max 150 words) covering:
        1. BUY, SELL, or HOLD recommendation with reasoning
        2. Competitive playability (which formats/archetypes use it)
        3. Price outlook (is it likely to go up or down and why)
        4. Any special collectibility factors (alternate art, foil premium, reserved list, etc.)

        Be direct and actionable. No disclaimers.
        """

        guard let result = await GeminiVisionService.generateInsight(prompt: prompt) else {
            error = "Failed to generate insight. Check Gemini settings."
            return
        }

        insight = result
        let dateStr = Self.dateFormatter.string(from: Date())
        insightDate = dateStr

        // Save to DB
        if let repo = cardRepository as? LocalCardRepository {
            try? await repo.databaseManager.saveInsight(
                scryfallID: card.scryfallID,
                insight: result,
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
