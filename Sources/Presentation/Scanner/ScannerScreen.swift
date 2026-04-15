import SwiftUI
import PhotosUI

// MARK: - Scanner Screen

/// The main scanner screen that presents a photo picker for selecting MTG card
/// images, processes them through OCR, and displays identified cards.
struct ScannerScreen: View {

    @Bindable var viewModel: CardScannerViewModel
    let pipeline: CardIdentificationPipelineProtocol
    let repository: CardRepositoryProtocol?
    let deckRepository: DeckListRepository?

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showDeckScan = false
    @State private var showImageSplitter = false

    var body: some View {
        ZStack {
            MD3Theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                MD3TopAppBar(title: "MTG Keyan")

                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomBar
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await viewModel.processSelectedPhotos(newItems)
                selectedItems = []
            }
        }
        .sheet(isPresented: $showDeckScan) {
            DeckScanScreen(
                viewModel: DeckScanViewModel(pipeline: pipeline),
                repository: repository,
                deckRepository: deckRepository,
                correctionService: viewModel.correctionService
            )
        }
        .sheet(isPresented: $showImageSplitter) {
            NavigationStack {
                ImageSplitterScreen(pipeline: pipeline, deckRepository: deckRepository, cardRepository: repository, correctionService: viewModel.correctionService)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.scanState {
        case .idle:
            idleView
        case .processing(let current, let total):
            processingView(current: current, total: total)
        case .completed:
            completedView(cards: viewModel.scannedCards)
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "viewfinder")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(MD3Theme.primary)

            Text("Identify a card")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(MD3Theme.onBackground)

            Text("Pick photos to scan, take a single live shot, or scan a whole deck photo at once.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                PhotoPickerView(selectedItems: $selectedItems)

                NavigationLink(destination: LiveScannerView(
                    pipeline: pipeline,
                    correctionService: viewModel.correctionService,
                    repository: repository,
                    deckRepository: deckRepository,
                    onCardsScanned: { cards in
                        viewModel.scannedCards = cards
                        viewModel.scanState = .completed(cards)
                    }
                )) {
                    HStack {
                        Image(systemName: "camera.viewfinder")
                        Text("Live Scan")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.primary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .overlay(
                        Capsule()
                            .stroke(MD3Theme.outline, lineWidth: 1)
                    )
                }

                Button {
                    showDeckScan = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.grid.2x2")
                        Text("Scan Deck Photo")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.primary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .overlay(
                        Capsule()
                            .stroke(MD3Theme.outline, lineWidth: 1)
                    )
                }

                Button {
                    showImageSplitter = true
                } label: {
                    HStack {
                        Image(systemName: "scissors")
                        Text("Split Cards")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.primary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .overlay(
                        Capsule()
                            .stroke(MD3Theme.outline, lineWidth: 1)
                    )
                }
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Processing View

    private func processingView(current: Int, total: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: viewModel.processingProgress) {
                Text("Processing \(current) of \(total) cards...")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onBackground)
            }
            .progressViewStyle(.linear)
            .tint(MD3Theme.primary)
            .padding(.horizontal, 48)

            Text("Identifying cards...")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            Spacer()
        }
    }

    // MARK: - Completed View

    private func completedView(cards: [Card]) -> some View {
        Group {
            if cards.isEmpty {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(MD3Theme.onSurfaceVariant)

                    Text("No cards identified")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onBackground)

                    Text("Try selecting clearer photos with the card name visible.")
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                }
            } else {
                ScannedCardsListView(
                    cards: cards,
                    repository: repository,
                    deckRepository: deckRepository,
                    onCorrection: { index, correctedCard in
                        Task {
                            await viewModel.correctCard(
                                at: index,
                                to: correctedCard,
                                originalImage: nil
                            )
                        }
                    }
                ) {
                    viewModel.resetScan()
                }
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(MD3Theme.error)

            Text("Error")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onBackground)

            Text(message)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            MD3FilledButton("Try Again") {
                viewModel.resetScan()
            }

            Spacer()
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        if case .completed = viewModel.scanState {
            VStack(spacing: 0) {
                Divider()
                    .background(MD3Theme.outlineVariant)

                HStack(spacing: 16) {
                    PhotoPickerView(selectedItems: $selectedItems)

                    MD3OutlinedButton("Reset") {
                        viewModel.resetScan()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(MD3Theme.surface)
                .md3Elevation(2)
            }
        }
    }
}

