import SwiftUI
import PhotosUI

// MARK: - Scanner Screen

/// The main scanner screen that presents a photo picker for selecting MTG card
/// images, processes them through OCR, and displays identified cards.
struct ScannerScreen: View {

    @Bindable var viewModel: CardScannerViewModel
    let pipeline: CardIdentificationPipelineProtocol
    let repository: CardRepositoryProtocol?

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showDeckScan = false

    var body: some View {
        ZStack {
            MD3Theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                MD3TopAppBar(title: "MTG Card Identifier")

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
            DeckScanScreen(viewModel: DeckScanViewModel(pipeline: pipeline))
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
        case .completed(let cards):
            completedView(cards: cards)
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)

            Text("Identify your MTG cards")
                .font(MD3Typography.headlineSmall)
                .foregroundStyle(MD3Theme.onBackground)

            Text("Select one photo per card. You can select multiple photos at once to identify several cards.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotoPickerView(selectedItems: $selectedItems)
                .padding(.top, 8)

            MD3OutlinedButton("Scan Deck Photo") {
                showDeckScan = true
            }

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

