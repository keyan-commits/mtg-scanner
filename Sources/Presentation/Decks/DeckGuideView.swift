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
    /// Set+collector from the deck items keyed by lowercased card name.
    /// Used to resolve the exact printing in the deck.
    let deckItemPrintings: [String: (set: String, collector: String)]

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

    /// Pre-resolve deck card names using the deck's actual set+collector
    /// so referenced cards link to the correct printing (e.g. Ice Age, not Strixhaven).
    private func resolveDeckCards() async {
        guard let repo = cardRepository else { return }
        for (lowerName, printing) in deckItemPrintings {
            guard deckCardLookup[lowerName] == nil else { continue }
            if let card = try? await repo.fetchCard(set: printing.set, collectorNumber: printing.collector) {
                deckCardLookup[lowerName] = card
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

// MARK: - Deck Guide Sheet (full screen, no preview)

/// Standalone sheet that shows the full deck guide directly.
/// Used from DeckDetailView to avoid List tap issues.
struct DeckGuideSheet: View {
    let deckName: String
    let format: String?
    let mainboard: [(name: String, quantity: Int)]
    let sideboard: [(name: String, quantity: Int)]
    let source: String?
    let cardRepository: CardRepositoryProtocol?
    let deckItemPrintings: [String: (set: String, collector: String)]

    @State private var guide: String?
    @State private var guideDate: String?
    @State private var isGenerating: Bool = false
    @State private var error: String?
    @State private var deckCardLookup: [String: Card] = [:]

    @Environment(\.dismiss) private var dismiss

    private var storageKey: String { "deckGuide_\(deckName)_\(format ?? "freeform")" }
    private var dateKey: String { "deckGuideDate_\(deckName)_\(format ?? "freeform")" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let guide {
                        // Render with proper markdown (bold headers) + tappable card links
                        let md = (try? AttributedString(markdown: guide, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(guide)
                        Text(md)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)

                        // Card chips
                        let cardNames = extractCardNames(from: guide)
                        if !cardNames.isEmpty {
                            Divider()
                            Text("Tap to view card details:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(cardNames, id: \.self) { name in
                                    cardChip(name)
                                }
                            }
                        }
                    } else if isGenerating {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Generating deck guide…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                    } else {
                        Button {
                            Task { await generateGuide() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "book.pages")
                                Text("Generate Deck Guide")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(MD3Theme.background)
            .navigationTitle("Deck Guide — \(deckName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let guideDate {
                        Text(guideDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if guide != nil {
                            if isGenerating {
                                ProgressView().scaleEffect(0.6)
                            } else {
                                Button {
                                    Task { await generateGuide() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                        }
                        Button("Done") { dismiss() }
                    }
                }
            }
            .task {
                guide = UserDefaults.standard.string(forKey: storageKey)
                guideDate = UserDefaults.standard.string(forKey: dateKey)
                await resolveDeckCards()
            }
        }
    }

    // MARK: - Card Chips

    @State private var resolvedCards: [String: Card] = [:]
    @State private var selectedCard: Card?
    @State private var showCardDetail: Bool = false

    private func cardChip(_ name: String) -> some View {
        let key = name.lowercased()
        let card = resolvedCards[key] ?? deckCardLookup[key]
        return NavigationLink {
            if let card {
                CardDetailView(card: card, repository: cardRepository, deckRepository: nil, onScanAnother: {})
            }
        } label: {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(card != nil ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(card != nil ? MD3Theme.primary : MD3Theme.surfaceVariant)
                .clipShape(Capsule())
        }
        .disabled(card == nil)
        .task { await resolveCard(name) }
    }

    private func resolveCard(_ name: String) async {
        let key = name.lowercased()
        guard resolvedCards[key] == nil else { return }
        if let deckCard = deckCardLookup[key] {
            resolvedCards[key] = deckCard
            return
        }
        guard let repo = cardRepository else { return }
        let resolver = CardResolver(cardRepository: repo)
        if let card = await resolver.resolve(name: name, strategy: .cheapest, allowFuzzyFallback: false) {
            resolvedCards[key] = card
        }
    }

    private func extractCardNames(from text: String) -> [String] {
        let headers: Set<String> = ["how to play", "key cards & synergies", "matchups to watch",
                                     "sideboard strategy", "improvement suggestions"]
        var names: [String] = []
        var seen = Set<String>()
        let pattern = /\*\*([^*]+)\*\*/
        for match in text.matches(of: pattern) {
            let name = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = name.lowercased()
            guard !headers.contains(lower), !name.hasSuffix(":"), name.count >= 3, !seen.contains(lower) else { continue }
            seen.insert(lower)
            names.append(name)
        }
        return names
    }

    // MARK: - Resolution & Generation

    private func resolveDeckCards() async {
        guard let repo = cardRepository else { return }
        for (lowerName, printing) in deckItemPrintings {
            guard deckCardLookup[lowerName] == nil else { continue }
            if let card = try? await repo.fetchCard(set: printing.set, collectorNumber: printing.collector) {
                deckCardLookup[lowerName] = card
            }
        }
    }

    private func generateGuide() async {
        isGenerating = true
        error = nil
        defer { isGenerating = false }

        let mainList = mainboard.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
        let sideList = sideboard.isEmpty ? "No sideboard" : sideboard.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
        let formatStr = format ?? "Unknown"
        let sourceInfo = source.map { "\nSource: \($0)" } ?? ""
        let totalCards = mainboard.reduce(0) { $0 + $1.quantity }
        let deckSizeNote = totalCards > 60 ? "\nNote: This deck has \(totalCards) cards." : ""

        let prompt = """
        You are an expert MTG deck coach. Provide a comprehensive guide.

        Deck: \(deckName)
        Format: \(formatStr)\(sourceInfo)\(deckSizeNote)
        Mainboard (\(totalCards) cards): \(mainList)
        Sideboard: \(sideList)

        Return a guide (300-400 words) with these sections. Use **bold** for section headers and **bold** for card name references:

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
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        guideDate = dateStr
        UserDefaults.standard.set(result, forKey: storageKey)
        UserDefaults.standard.set(dateStr, forKey: dateKey)
    }
}
