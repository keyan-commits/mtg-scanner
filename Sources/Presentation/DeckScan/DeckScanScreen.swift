import SwiftUI
import PhotosUI
import CoreImage

// MARK: - Deck Scan Screen

/// The main deck scanning screen that guides users through photographing cards
/// laid out on a table, adjusting a grid overlay, and identifying all cards.
struct DeckScanScreen: View {

    @Bindable var viewModel: DeckScanViewModel
    var repository: (any CardRepositoryProtocol)?
    var correctionService: CardCorrectionService?

    @State private var selectedItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MD3Theme.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MD3TopAppBar(title: "Deck Photo Scan") {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(MD3Theme.onSurface)
                        }
                    }

                    contentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await loadImage(from: newItem)
                    selectedItem = nil
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.scanState {
        case .selectingPhoto:
            selectingPhotoView

        case .adjustingGrid:
            adjustingGridView

        case .processing(let current, let total):
            processingView(current: current, total: total)

        case .results:
            resultsView
        }
    }

    // MARK: - Selecting Photo

    private var selectingPhotoView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)

            Text("Scan Deck Photo")
                .font(MD3Typography.headlineSmall)
                .foregroundStyle(MD3Theme.onBackground)

            Text("Take a photo of your deck laid out on a table. Arrange cards in a grid for best results.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Select Deck Photo", systemImage: "photo.on.rectangle.angled")
                    .font(MD3Typography.labelLarge)
                    .foregroundStyle(MD3Theme.onPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .frame(minHeight: 40)
                    .background(MD3Theme.primary)
                    .clipShape(MD3Shape.full)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Adjusting Grid

    private var adjustingGridView: some View {
        Group {
            if let image = viewModel.sourceImage {
                DeckGridOverlayView(
                    image: image,
                    rows: Bindable(viewModel).rows,
                    columns: Bindable(viewModel).columns
                ) {
                    Task {
                        await viewModel.processGrid()
                    }
                }
            }
        }
    }

    // MARK: - Processing

    private func processingView(current: Int, total: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: viewModel.processingProgress) {
                Text("Identifying card \(current) of \(total)...")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onBackground)
            }
            .progressViewStyle(.linear)
            .tint(MD3Theme.primary)
            .padding(.horizontal, 48)

            Text("Processing grid cells...")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            Spacer()
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        DecklistResultView(viewModel: viewModel, repository: repository, correctionService: correctionService)
    }

    // MARK: - Image Loading

    private func loadImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            return
        }
        viewModel.setImage(cgImage)
    }
}
