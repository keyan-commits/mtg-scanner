import SwiftUI
import PhotosUI

struct BatchScanScreen: View {
    @State private var viewModel: BatchScanViewModel
    @State private var correctingIndex: Int?
    @Environment(\.dismiss) private var dismiss
    @Bindable private var currencyService = CurrencyService.shared

    init(pipeline: CardIdentificationPipelineProtocol,
         cardRepository: CardRepositoryProtocol? = nil,
         deckRepository: DeckListRepository? = nil) {
        self._viewModel = State(initialValue: BatchScanViewModel(
            pipeline: pipeline,
            cardRepository: cardRepository,
            deckRepository: deckRepository
        ))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .selecting:
                selectingView
            case .processing(let current, let total):
                processingView(current: current, total: total)
            case .results:
                resultsView
            case .error(let message):
                errorView(message)
            }
        }
        .navigationTitle("Batch Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if case .results = viewModel.state {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: Binding(
            get: { correctingIndex.map { CorrectionTarget(index: $0) } },
            set: { correctingIndex = $0?.index }
        )) { target in
            if let repo = viewModel.cardRepository, target.index < viewModel.identifiedCards.count {
                CardCorrectionView(
                    repository: repo,
                    currentCard: viewModel.identifiedCards[target.index].card,
                    onCorrection: { newCard in
                        viewModel.replaceCard(at: target.index, with: newCard)
                        correctingIndex = nil
                    }
                )
            }
        }
        .alert("Saved to Photos", isPresented: $viewModel.showSaveAlert) {
            Button("OK") { viewModel.showSaveAlert = false }
        } message: {
            if let err = viewModel.saveError {
                Text(err)
            } else {
                Text("\(viewModel.savedCount) card\(viewModel.savedCount == 1 ? "" : "s") saved.")
            }
        }
        .task { await currencyService.refreshIfStale() }
    }

    // MARK: - Selecting

    private var selectingView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.stack")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(MD3Theme.primary)

            Text("Batch Card Scan")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(MD3Theme.onBackground)

            Text("Select multiple card photos from your library.\nGemini AI will identify all cards in one batch.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !GeminiVisionService.isConfigured {
                Text("Set up Gemini API key in Settings first")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                PhotosPicker(
                    selection: $viewModel.selectedPhotos,
                    maxSelectionCount: 300,
                    matching: .images
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Select Photos")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(MD3Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("Up to 300 photos per batch \u{00B7} multi-card photos OK")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

            Spacer()
        }
        .onChange(of: viewModel.selectedPhotos) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task { await viewModel.loadAndProcess() }
        }
    }

    // MARK: - Processing

    private func processingView(current: Int, total: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: Double(current), total: Double(total)) {
                Text("Processing photos...")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onBackground)
            }
            .progressViewStyle(.linear)
            .tint(MD3Theme.primary)
            .padding(.horizontal, 48)

            Text("\(current) of \(total)")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            if current == total {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Sending to Gemini AI...")
                        .font(.subheadline)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }

            Spacer()
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                photoStrip
                analysisCard
                identifiedSection
                actionButtons
                rescanButton
                Spacer(minLength: 32)
            }
            .padding(.top, 12)
        }
        .background(MD3Theme.background)
    }

    private var summaryCard: some View {
        MD3Card {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.cardCount) card\(viewModel.cardCount == 1 ? "" : "s") from \(viewModel.photosWithCards) of \(viewModel.totalPhotos) photo\(viewModel.totalPhotos == 1 ? "" : "s")")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                    if viewModel.hasAnyPrice {
                        Text("Total value: \(formattedTotalValue)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(MD3Theme.primary)
                            .monospacedDigit()
                    }
                    Text("Payload: \(viewModel.payloadMB)")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                    if !viewModel.failedIndices.isEmpty {
                        Text("\(viewModel.failedIndices.count) photo\(viewModel.failedIndices.count == 1 ? "" : "s") had no recognizable cards")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    /// Renders `viewModel.totalValueUSD` in the user's preferred currency.
    /// Falls back to USD when the rate is unavailable so we never show a
    /// blank value next to "Total value:".
    private var formattedTotalValue: String {
        let usd = viewModel.totalValueUSD
        let preferred = LocalCurrency.current
        if let converted = currencyService.convert(usd, to: preferred) {
            return LocalCurrency.format(converted, currency: preferred)
        }
        return LocalCurrency.format(usd, currency: "USD")
    }

    /// Horizontal strip of source photos with bbox overlays so the user can
    /// visually map detections back to the photo they came from.
    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Enumerate the array directly so the closure captures the CGImage by
                // value. Previously used `ForEach(0..<count, id: \.self)` which left
                // a window during reset() where the index outran the cleared array.
                ForEach(Array(viewModel.loadedImages.enumerated()), id: \.offset) { offset, image in
                    photoThumbnail(image: image, photoIndex: offset)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func photoThumbnail(image: CGImage, photoIndex: Int) -> some View {
        let bboxes = viewModel.identifiedCards
            .filter { $0.imageIndex == photoIndex }
            .compactMap(\.boundingBox)
        return Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                GeometryReader { geo in
                    ForEach(Array(bboxes.enumerated()), id: \.offset) { _, bbox in
                        Rectangle()
                            .stroke(Color.green, lineWidth: 2)
                            .frame(
                                width: max(2, CGFloat(bbox.w) * geo.size.width),
                                height: max(2, CGFloat(bbox.h) * geo.size.height)
                            )
                            .position(
                                x: (CGFloat(bbox.x) + CGFloat(bbox.w) / 2) * geo.size.width,
                                y: (CGFloat(bbox.y) + CGFloat(bbox.h) / 2) * geo.size.height
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var analysisCard: some View {
        if let analysis = viewModel.analysis, !analysis.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(MD3Theme.primary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gemini Analysis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MD3Theme.primary.opacity(0.7))
                        .textCase(.uppercase)
                    Text(analysis)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MD3Theme.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
        }
    }

    private var identifiedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Identified Cards")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MD3Theme.onSurface)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(viewModel.identifiedCards.enumerated()), id: \.offset) { offset, entry in
                    identifiedRow(at: offset, entry: entry)
                    if offset < viewModel.identifiedCards.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private func identifiedRow(at index: Int, entry: BatchIdentifiedCard) -> some View {
        HStack(spacing: 8) {
            // Per-card crop from the bbox; falls back to the full source photo
            // when no bbox is available.
            if let thumb = viewModel.cardThumbnails[index] {
                Image(decorative: thumb, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.card.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                Text("\(entry.card.set.name) #\(entry.card.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer()

            foilToggle(for: index)

            quantityStepper(for: index)

            if let unit = viewModel.unitPriceUSD(at: index) {
                Text(String(format: "$%.2f", unit))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MD3Theme.primary)
                    .monospacedDigit()
            }

            if viewModel.cardRepository != nil {
                Button {
                    correctingIndex = index
                } label: {
                    Text("Fix")
                        .font(.system(size: 13, weight: .semibold))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func quantityStepper(for index: Int) -> some View {
        ScannedCardQuantityStepper(
            quantity: viewModel.quantity(at: index),
            onDecrement: { viewModel.decrementQuantity(at: index) },
            onIncrement: { viewModel.incrementQuantity(at: index) }
        )
    }

    /// Foil pill — taps toggle row foil state. Disabled (always-on) for
    /// foil-only printings (FNM, Secret Lair foils, etc.) where there's
    /// no nonfoil version to switch to.
    private func foilToggle(for index: Int) -> some View {
        let isFoil = viewModel.isFoil(at: index)
        let foilOnly = viewModel.foilOnly(at: index)
        return Button {
            if !foilOnly { viewModel.toggleFoil(at: index) }
        } label: {
            Text("Foil")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(isFoil ? .white : MD3Theme.onSurfaceVariant)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isFoil ? Color.purple : MD3Theme.surfaceVariant)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        isFoil ? Color.purple.opacity(0.4) : MD3Theme.outlineVariant,
                        lineWidth: 1
                    )
                )
                .opacity(foilOnly ? 0.85 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(foilOnly)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if viewModel.addedToCollection > 0 {
                statusPill(icon: "checkmark.circle.fill", color: .green,
                           text: "Added \(viewModel.addedToCollection) cards to collection")
            } else if viewModel.addedToDeck != nil {
                statusPill(icon: "checkmark.circle.fill", color: .green, text: "Deck created!")
            } else {
                Button {
                    viewModel.addAllToCollection()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.rectangle.on.rectangle")
                        Text("Add \(viewModel.cardCount) to Collection")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.cardCount > 0 ? Color.green : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.cardCount == 0)

                Button {
                    let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
                    viewModel.createDeck(name: "Batch Scan \(dateStr)")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                        Text("Create Deck")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.cardCount > 0 ? MD3Theme.primary : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.cardCount == 0)
            }

            Button {
                Task { await viewModel.saveCardsToPhotos() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: viewModel.saveSuccess ? "checkmark.circle.fill" : "square.and.arrow.down.on.square")
                    }
                    Text(saveButtonLabel)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(saveButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.cardCount == 0 || viewModel.isSaving || viewModel.saveSuccess)
        }
        .padding(.horizontal, 16)
    }

    private var saveButtonLabel: String {
        if viewModel.isSaving { return "Saving..." }
        if viewModel.saveSuccess { return "Saved to Photos" }
        return "Save \(viewModel.cardCount) Card\(viewModel.cardCount == 1 ? "" : "s") to Photos"
    }

    private var saveButtonBackground: Color {
        if viewModel.cardCount == 0 || viewModel.isSaving || viewModel.saveSuccess {
            return Color.gray
        }
        return MD3Theme.primary
    }

    private func statusPill(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rescanButton: some View {
        Button {
            viewModel.reset()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                Text("Scan More")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(MD3Theme.primary)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(MD3Theme.error)
            Text("Scan Failed")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onBackground)
            Text(message)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                viewModel.reset()
            } label: {
                Text("Try Again")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(MD3Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}

private struct CorrectionTarget: Identifiable {
    let index: Int
    var id: Int { index }
}
