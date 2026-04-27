import SwiftUI
import PhotosUI

struct BatchScanScreen: View {
    @State private var viewModel: BatchScanViewModel
    @Environment(\.dismiss) private var dismiss

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

                Text("Up to 300 photos per batch \u{00B7} ~40KB each after downscaling")
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
                // Summary card
                MD3Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(viewModel.identifiedCount) of \(viewModel.totalPhotos) identified")
                                    .font(MD3Typography.titleMedium)
                                    .foregroundStyle(MD3Theme.onSurface)
                                Text("Payload: \(viewModel.payloadMB)")
                                    .font(.caption)
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                            }
                            Spacer()
                        }
                        if !viewModel.failedIndices.isEmpty {
                            Text("\(viewModel.failedIndices.count) photo\(viewModel.failedIndices.count == 1 ? "" : "s") could not be identified")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // Action buttons
                if viewModel.addedToCollection > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Added \(viewModel.addedToCollection) cards to collection")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                } else if viewModel.addedToDeck != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Deck created!")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.addAllToCollection()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "tray.and.arrow.down")
                                Text("Add to Collection")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(MD3Theme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.identifiedCards.isEmpty)

                        Button {
                            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
                            viewModel.createDeck(name: "Batch Scan \(dateStr)")
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.stack.badge.plus")
                                Text("Create Deck")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MD3Theme.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(MD3Theme.outline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.identifiedCards.isEmpty)
                    }
                    .padding(.horizontal, 16)
                }

                // Card list
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.identifiedCards.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 12) {
                            // Thumbnail
                            if entry.index < viewModel.loadedImages.count {
                                let img = viewModel.loadedImages[entry.index]
                                Image(decorative: img, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 40, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.card.name)
                                    .font(MD3Typography.bodyMedium)
                                    .foregroundStyle(MD3Theme.onSurface)
                                    .lineLimit(1)
                                Text("\(entry.card.set.name) #\(entry.card.collectorNumber)")
                                    .font(.caption2)
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                            }

                            Spacer()

                            if let usd = entry.card.prices.usd {
                                Text("$\(usd)")
                                    .font(MD3Typography.labelMedium)
                                    .foregroundStyle(MD3Theme.primary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if entry.index != viewModel.identifiedCards.last?.index {
                            Divider().padding(.leading, 68)
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

                // Scan more button
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
                .padding(.top, 8)

                Spacer(minLength: 32)
            }
            .padding(.top, 16)
        }
        .background(MD3Theme.background)
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
