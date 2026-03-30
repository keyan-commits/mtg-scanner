import SwiftUI

// MARK: - Decklist Result View

/// Displays the identified decklist grouped by card type, with quantities,
/// prices, export, deck identification, and training data export actions.
struct DecklistResultView: View {

    @Bindable var viewModel: DeckScanViewModel
    var mtgTop8Service: MTGTop8ServiceProtocol?
    var trainingDataExporter: TrainingDataExporter?
    var repository: (any CardRepositoryProtocol)?
    var correctionService: CardCorrectionService?

    @State private var deckIdentificationResult: DeckIdentificationResult?
    @State private var isIdentifyingDeck: Bool = false
    @State private var showDeckIdentification: Bool = false
    @State private var trainingDataCount: Int = 0
    @State private var correctionItem: CorrectionItem?

    struct CorrectionItem: Identifiable {
        let id = UUID()
        let cardIndex: Int  // index in identifiedCards
    }

    private var decklist: [(name: String, card: Card, quantity: Int)] {
        viewModel.buildDecklist()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if decklist.isEmpty {
                emptyState
            } else {
                decklistContent
            }

            footer
        }
        .background(MD3Theme.background)
        .onAppear {
            trainingDataCount = trainingDataExporter?.trainingDataCount() ?? 0
        }
        .sheet(item: $correctionItem) { item in
            if let repository {
                CardCorrectionView(
                    repository: repository,
                    currentCard: item.cardIndex < viewModel.identifiedCards.count
                        ? viewModel.identifiedCards[item.cardIndex] : nil,
                    onCorrection: { correctedCard in
                        if item.cardIndex < viewModel.identifiedCards.count {
                            viewModel.identifiedCards[item.cardIndex] = correctedCard
                            // Feed correction to FeaturePrint cache — ML learns
                            if let service = correctionService,
                               let image = viewModel.sourceImage {
                                let cellWidth = image.width / viewModel.columns
                                let cellHeight = image.height / viewModel.rows
                                let row = item.cardIndex / viewModel.columns
                                let col = item.cardIndex % viewModel.columns
                                let rect = CGRect(x: col * cellWidth, y: row * cellHeight, width: cellWidth, height: cellHeight)
                                if let cellImage = image.cropping(to: rect) {
                                    Task {
                                        await service.applyCorrection(correctCard: correctedCard, originalCardImage: cellImage)
                                    }
                                }
                            }
                        }
                        correctionItem = nil
                    }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Decklist (\(viewModel.identifiedCards.count) cards identified)")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onBackground)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.minus")
                .font(.system(size: 48))
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            Text("No cards identified")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            Text("Try a clearer photo with cards arranged in a regular grid.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Decklist Content

    private var decklistContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Deck identification & training data actions
                deckActionButtons

                ForEach(cardTypeGroups, id: \.category) { group in
                    Section {
                        ForEach(group.entries, id: \.name) { entry in
                            HStack(spacing: 8) {
                                NavigationLink(value: entry.card) {
                                    decklistRow(entry: entry)
                                }
                                .buttonStyle(.plain)

                                if repository != nil {
                                    Button {
                                        if let idx = viewModel.identifiedCards.firstIndex(where: { $0.id == entry.card.id }) {
                                            correctionItem = CorrectionItem(cardIndex: idx)
                                        }
                                    } label: {
                                        Text("Fix")
                                            .font(MD3Typography.labelLarge)
                                            .foregroundStyle(MD3Theme.primary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(MD3Theme.outline, lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(group.category)
                            .font(MD3Typography.titleSmall)
                            .foregroundStyle(MD3Theme.primary)
                            .padding(.top, 4)
                    }
                }

                // Deck identification results
                if showDeckIdentification, let result = deckIdentificationResult {
                    Divider()
                        .padding(.vertical, 8)

                    DeckIdentificationView(result: result)
                }
            }
            .padding(16)
        }
        .navigationDestination(for: Card.self) { card in
            CardDetailView(card: card) {}
        }
    }

    private func decklistRow(entry: (name: String, card: Card, quantity: Int)) -> some View {
        HStack(spacing: 8) {
            Text("\(entry.quantity)x")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.primary)
                .frame(width: 32, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.card.name)
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)

                    Text(raritySymbol(entry.card.rarity))
                        .font(.caption2)
                        .foregroundStyle(rarityColor(entry.card.rarity))
                }

                Text(entry.card.set.name)
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer()

            if let price = entry.card.prices.formattedPrice {
                Text(price)
                    .font(MD3Typography.labelMedium)
                    .foregroundStyle(MD3Theme.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Deck Action Buttons

    private var deckActionButtons: some View {
        VStack(spacing: 12) {
            if mtgTop8Service != nil {
                MD3FilledButton("Identify Deck") {
                    Task {
                        await identifyDeck()
                    }
                }
                .opacity(isIdentifyingDeck ? 0.6 : 1.0)
                .disabled(isIdentifyingDeck)

                if isIdentifyingDeck {
                    HStack {
                        ProgressView()
                        Text("Analyzing deck...")
                            .font(MD3Typography.bodySmall)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                            .padding(.leading, 8)
                    }
                }
            }

            if let exporter = trainingDataExporter {
                HStack {
                    MD3OutlinedButton("Export Training Data") {
                        _ = exporter.exportAll()
                    }

                    if trainingDataCount > 0 {
                        Text("\(trainingDataCount)")
                            .font(MD3Typography.labelSmall)
                            .foregroundStyle(MD3Theme.onPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MD3Theme.primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Deck Identification

    private func identifyDeck() async {
        guard let service = mtgTop8Service else { return }
        isIdentifyingDeck = true

        let identificationService = DeckIdentificationService(mtgTop8Service: service)
        let result = await identificationService.identifyDeck(cards: viewModel.identifiedCards)

        deckIdentificationResult = result
        showDeckIdentification = true
        isIdentifyingDeck = false
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Divider()
                .background(MD3Theme.outlineVariant)

            totalValueRow

            HStack(spacing: 12) {
                MD3OutlinedButton("Export") {
                    copyDecklistToClipboard()
                }

                MD3FilledButton("Scan Again") {
                    viewModel.reset()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MD3Theme.surface)
    }

    private var totalValueRow: some View {
        HStack {
            Text("Total Value")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onSurface)

            Spacer()

            Text(totalPrice)
                .font(MD3Typography.headlineSmall)
                .foregroundStyle(MD3Theme.primary)
        }
    }

    // MARK: - Computed Properties

    private var totalPrice: String {
        let total = decklist.compactMap { entry -> Double? in
            guard let usd = entry.card.prices.usd else { return nil }
            return Double(usd).map { $0 * Double(entry.quantity) }
        }.reduce(0, +)

        guard total > 0 else { return "--" }
        return String(format: "$%.2f", total)
    }

    // MARK: - Card Type Grouping

    private struct CardTypeGroup {
        let category: String
        let entries: [(name: String, card: Card, quantity: Int)]
    }

    private var cardTypeGroups: [CardTypeGroup] {
        let categoryOrder = ["Creatures", "Planeswalkers", "Instants", "Sorceries", "Enchantments", "Artifacts", "Lands", "Other"]

        var groups: [String: [(name: String, card: Card, quantity: Int)]] = [:]

        for entry in decklist {
            let category = categorize(typeLine: entry.card.typeLine)
            groups[category, default: []].append(entry)
        }

        return categoryOrder.compactMap { category in
            guard let entries = groups[category], !entries.isEmpty else { return nil }
            return CardTypeGroup(category: category, entries: entries)
        }
    }

    private func categorize(typeLine: String) -> String {
        let lower = typeLine.lowercased()
        if lower.contains("creature") { return "Creatures" }
        if lower.contains("planeswalker") { return "Planeswalkers" }
        if lower.contains("instant") { return "Instants" }
        if lower.contains("sorcery") { return "Sorceries" }
        if lower.contains("enchantment") { return "Enchantments" }
        if lower.contains("artifact") { return "Artifacts" }
        if lower.contains("land") { return "Lands" }
        return "Other"
    }

    // MARK: - Rarity

    private func raritySymbol(_ rarity: CardRarity) -> String {
        switch rarity {
        case .mythic: return "M"
        case .rare: return "R"
        case .uncommon: return "U"
        case .common: return "C"
        }
    }

    private func rarityColor(_ rarity: CardRarity) -> Color {
        switch rarity {
        case .mythic: return .orange
        case .rare: return .yellow
        case .uncommon: return .gray
        case .common: return Color(white: 0.5)
        }
    }

    // MARK: - Export

    private func copyDecklistToClipboard() {
        var lines: [String] = []
        for entry in decklist {
            lines.append("\(entry.quantity) \(entry.card.name)")
        }
        let text = lines.joined(separator: "\n")
        UIPasteboard.general.string = text
    }
}
