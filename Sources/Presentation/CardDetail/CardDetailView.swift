import SwiftUI

// MARK: - Card Detail View

/// Displays detailed information about an identified Magic card,
/// including its image, name, set, price, format legality, and oracle text.
struct CardDetailView: View {

    private let viewModel: CardDetailViewModel
    private let onScanAnother: () -> Void

    /// Creates a card detail view.
    /// - Parameters:
    ///   - card: The card to display.
    ///   - onScanAnother: Closure invoked when the user taps "Scan Another".
    init(card: Card, onScanAnother: @escaping () -> Void) {
        self.viewModel = CardDetailViewModel(card: card)
        self.onScanAnother = onScanAnother
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                cardImage
                cardHeader
                priceCard
                legalitySection
                DeckCompatibilityView(
                    card: viewModel.card,
                    edhrecService: EDHRECService(),
                    mtgTop8Service: MTGTop8Service()
                )
                oracleTextSection
                scanAnotherButton
            }
            .padding(16)
        }
        .background(MD3Theme.background)
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

            Text("\(viewModel.card.set.name) \u{2022} #\(viewModel.card.collectorNumber)")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Price Card

    @ViewBuilder
    private var priceCard: some View {
        if let price = viewModel.formattedPrice {
            MD3Card {
                HStack {
                    Text("Market Price")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    Spacer()

                    Text(price)
                        .font(MD3Typography.headlineSmall)
                        .foregroundStyle(MD3Theme.primary)
                }
                .padding(16)
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
        MD3OutlinedButton("Scan Another") {
            onScanAnother()
        }
        .padding(.top, 8)
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
