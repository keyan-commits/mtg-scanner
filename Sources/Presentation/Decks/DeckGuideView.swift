import SwiftUI

/// AI-generated deck guide. Shows strategy, matchups, sideboard plan,
/// and improvement suggestions. Persisted to UserDefaults per deck name.
struct DeckGuideView: View {

    let deckName: String
    let format: String?
    let mainboard: [(name: String, quantity: Int)]
    let sideboard: [(name: String, quantity: Int)]
    let source: String?
    let cardRepository: CardRepositoryProtocol?

    @State private var guide: String?
    @State private var guideDate: String?
    @State private var isGenerating: Bool = false
    @State private var error: String?
    @State private var showFullGuide: Bool = false
    /// Lookup of deck card names → resolved Card for correct version matching.
    @State private var deckCardLookup: [String: Card] = [:]

    private var isConfigured: Bool { GeminiVisionService.isConfigured }
    private var remainingQuota: Int { max(0, 1000 - GeminiVisionService.dailyUsage) }

    // Persist guides keyed by deck name + format
    private var storageKey: String { "deckGuide_\(deckName)_\(format ?? "freeform")" }
    private var dateKey: String { "deckGuideDate_\(deckName)_\(format ?? "freeform")" }

    var body: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "book.pages")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text("AI Deck Guide")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                    Spacer()
                    if let guideDate {
                        Text(guideDate)
                            .font(.system(size: 9))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                    if guide != nil {
                        if isGenerating {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button {
                                Task { await generateGuide() }
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
                if let guide {
                    LinkedCardText(
                        text: String(guide.prefix(300)),
                        cardRepository: cardRepository,
                        deckCards: deckCardLookup,
                        font: MD3Typography.bodySmall
                    )
                    Button {
                        showFullGuide = true
                    } label: {
                        Text("Read more")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(MD3Theme.primary)
                    }
                    .buttonStyle(.plain)
                } else if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Generating deck guide…")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                } else if !isConfigured {
                    Text("Set up Gemini API key in Settings to enable AI deck guides")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                } else {
                    Button {
                        Task { await generateGuide() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "book.pages")
                            Text("Generate Deck Guide")
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
        .sheet(isPresented: $showFullGuide) {
            guideFullScreen
        }
        .task {
            await loadCachedGuide()
        }
    }

    // MARK: - Full Screen

    private var guideFullScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let guide {
                        LinkedCardText(
                            text: guide,
                            cardRepository: cardRepository,
                            deckCards: deckCardLookup
                        )
                    }
                }
                .padding(20)
            }
            .background(MD3Theme.background)
            .navigationTitle("Deck Guide — \(deckName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFullGuide = false }
                }
            }
        }
    }

    /// Pre-resolve deck card names so LinkedCardText can match the correct version.
    private func resolveDeckCards() async {
        guard let repo = cardRepository else { return }
        let resolver = CardResolver(cardRepository: repo)
        let allNames = Set(mainboard.map(\.name) + sideboard.map(\.name))
        for name in allNames {
            if deckCardLookup[name.lowercased()] == nil {
                if let card = await resolver.resolve(name: name, strategy: .cheapest) {
                    deckCardLookup[name.lowercased()] = card
                }
            }
        }
    }

    // MARK: - Cache

    private func loadCachedGuide() async {
        guide = UserDefaults.standard.string(forKey: storageKey)
        guideDate = UserDefaults.standard.string(forKey: dateKey)
        await resolveDeckCards()
    }

    private func saveGuide(_ text: String, date: String) {
        UserDefaults.standard.set(text, forKey: storageKey)
        UserDefaults.standard.set(date, forKey: dateKey)
    }

    // MARK: - Generate

    private func generateGuide() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }

        let mainList = mainboard.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
        let sideList = sideboard.isEmpty ? "No sideboard" : sideboard.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
        let formatStr = format ?? "Unknown"
        let sourceInfo = source.map { "\nSource: \($0)" } ?? ""
        let totalCards = mainboard.reduce(0) { $0 + $1.quantity }
        let deckSizeNote = totalCards > 60 ? "\nNote: This deck has \(totalCards) cards (standard is 60 mainboard + 15 sideboard). Address this in your suggestions." : ""

        let prompt = """
        You are an expert MTG deck coach. Analyze this deck and provide a comprehensive guide.

        Deck: \(deckName)
        Format: \(formatStr)\(sourceInfo)\(deckSizeNote)
        Mainboard (\(totalCards) cards): \(mainList)
        Sideboard: \(sideList)

        Return a guide (300-400 words) with these sections separated by blank lines. Use **bold** for section headers and **bold** for card name references:

        **How to Play**
        Core game plan, key combos, sequencing, and win conditions.

        **Key Cards & Synergies**
        The most important cards and how they work together.

        **Matchups to Watch**
        Top 3-4 tough matchups and how to approach each.

        **Sideboard Strategy**
        What to bring in/out for common matchups.

        **Improvement Suggestions**
        2-3 specific cards to consider adding or cutting, with reasoning.

        Be specific to this exact decklist. Reference actual card names from the list.
        """

        guard let result = await GeminiVisionService.generateInsight(prompt: prompt) else {
            error = "Failed to generate guide. Check Gemini settings."
            return
        }

        guide = result
        let dateStr = Self.dateFormatter.string(from: Date())
        guideDate = dateStr
        saveGuide(result, date: dateStr)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()
}
