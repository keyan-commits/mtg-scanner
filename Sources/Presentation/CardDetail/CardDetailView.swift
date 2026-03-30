import SwiftUI

// MARK: - Card Detail View

/// Displays detailed information about an identified Magic card,
/// including its image, name, set, price, format legality, and oracle text.
struct CardDetailView: View {

    private let viewModel: CardDetailViewModel
    private let onScanAnother: () -> Void
    private let repository: CardRepositoryProtocol?
    private let onCorrection: ((Card) -> Void)?

    @State private var showCorrection = false

    /// Creates a card detail view.
    /// - Parameters:
    ///   - card: The card to display.
    ///   - repository: Optional repository for card correction search.
    ///   - onCorrection: Optional callback when the user corrects the card.
    ///   - onScanAnother: Closure invoked when the user taps "Scan Another".
    init(
        card: Card,
        repository: CardRepositoryProtocol? = nil,
        onCorrection: ((Card) -> Void)? = nil,
        onScanAnother: @escaping () -> Void
    ) {
        self.viewModel = CardDetailViewModel(card: card)
        self.repository = repository
        self.onCorrection = onCorrection
        self.onScanAnother = onScanAnother
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                cardImage
                cardHeader
                PriceComparisonView(card: viewModel.card)
                legalitySection
                DeckCompatibilityView(
                    card: viewModel.card,
                    deckLookupService: DeckLookupService(
                        mtgTop8Service: MTGTop8Service(),
                        edhrecService: EDHRECService()
                    )
                )
                oracleTextSection
                scanAnotherButton
            }
            .padding(16)
        }
        .background(MD3Theme.background)
        .task {
            await loadVariantInfo()
        }
    }

    // MARK: - Card Image

    @ViewBuilder
    private var cardImage: some View {
        if let url = viewModel.cardImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    imagePlaceholder
                case .empty:
                    ProgressView()
                        .frame(height: 340)
                @unknown default:
                    imagePlaceholder
                }
            }
            .frame(maxHeight: 340)
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(MD3Theme.surfaceVariant)
            .frame(height: 340)
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.card.name)
                .font(MD3Typography.headlineMedium)
                .foregroundStyle(MD3Theme.onBackground)

            HStack(spacing: 6) {
                Text("\(viewModel.card.set.name) \u{2022} #\(viewModel.card.collectorNumber)")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)

                if let variant = viewModel.variantLabel {
                    Text(variant)
                        .font(MD3Typography.labelMedium)
                        .foregroundStyle(MD3Theme.onTertiaryContainer)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(MD3Theme.tertiaryContainer)
                        .clipShape(Capsule())
                }
            }

            if let artist = viewModel.artistLabel {
                Text(artist)
                    .font(MD3Typography.bodySmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

            if onCorrection != nil, repository != nil {
                Button {
                    showCorrection = true
                } label: {
                    Text("Wrong card? Tap to correct")
                        .font(MD3Typography.labelLarge)
                        .foregroundStyle(MD3Theme.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(MD3Theme.outline, lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showCorrection) {
            if let repository, let onCorrection {
                CardCorrectionView(
                    repository: repository,
                    currentCard: viewModel.card,
                    onCorrection: { correctedCard in
                        showCorrection = false
                        onCorrection(correctedCard)
                    }
                )
            }
        }
    }

    // MARK: - Legality Section

    private var legalitySection: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Format Legality")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)

                ForEach(viewModel.legalFormats, id: \.0) { format, status in
                    HStack {
                        Circle()
                            .fill(legalityColor(for: status))
                            .frame(width: 10, height: 10)

                        Text(format)
                            .font(MD3Typography.bodyMedium)
                            .foregroundStyle(MD3Theme.onSurface)

                        Spacer()

                        Text(legalityLabel(for: status))
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(legalityColor(for: status))
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Oracle Text

    @ViewBuilder
    private var oracleTextSection: some View {
        if let oracleText = viewModel.card.oracleText, !oracleText.isEmpty {
            MD3Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Oracle Text")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    Text(oracleText)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Scan Another Button

    private var scanAnotherButton: some View {
        MD3OutlinedButton("Identify Another") {
            onScanAnother()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant Cross-Reference

    private func loadVariantInfo() async {
        // If already has a variant label from collector number suffix, skip
        let number = viewModel.card.collectorNumber
        if let lastChar = number.last, lastChar.isLetter { return }

        // Cross-reference illustration_id to find matching variant in another set
        guard let illustrationID = viewModel.card.illustrationID else { return }

        do {
            let dbManager = try DatabaseManager()
            let sameArt = try await dbManager.findByIllustrationID(illustrationID)

            // Look for a matching card with a letter suffix collector number
            let knownNames: [String: [String: String]] = [
                "Mishra's Factory": ["a": "Spring", "b": "Summer", "c": "Autumn", "d": "Winter"],
                "Urza's Mine": ["a": "Pulley", "b": "Mouth", "c": "Clawed Sphere", "d": "Tower"],
                "Urza's Power Plant": ["a": "Sphere", "b": "Columns", "c": "Bug", "d": "Rock in Pot"],
                "Urza's Tower": ["a": "Forest", "b": "Shore", "c": "Plains", "d": "Mountains"],
                "Strip Mine": ["a": "No Horizon", "b": "Even Horizon", "c": "Tower", "d": "Uneven Horizon"],
            ]

            for record in sameArt {
                if let lastChar = record.collectorNumber.last, lastChar.isLetter {
                    let suffix = String(lastChar).lowercased()
                    let cardName = viewModel.card.name
                    if let named = knownNames[cardName]?[suffix] {
                        viewModel.crossReferencedVariant = named
                    } else if let artist = viewModel.card.artist {
                        let parts = artist.split(separator: " ")
                        viewModel.crossReferencedVariant = parts.last.map(String.init) ?? "Variant \(suffix.uppercased())"
                    } else {
                        viewModel.crossReferencedVariant = "Variant \(suffix.uppercased())"
                    }
                    return
                }
            }
        } catch {
            // Cross-reference failed, no variant label
        }
    }

    // MARK: - Helpers

    private func legalityColor(for status: LegalityStatus) -> Color {
        switch status {
        case .legal:
            return .green
        case .banned:
            return .red
        case .restricted:
            return .orange
        case .notLegal:
            return .gray
        }
    }

    private func legalityLabel(for status: LegalityStatus) -> String {
        switch status {
        case .legal:
            return "Legal"
        case .banned:
            return "Banned"
        case .restricted:
            return "Restricted"
        case .notLegal:
            return "Not Legal"
        }
    }
}
