import SwiftUI
import PhotosUI

/// Image splitting tool: detect cards, adjust regions, identify, save with prices.
struct ImageSplitterScreen: View {

    let pipeline: CardIdentificationPipelineProtocol?
    let deckRepository: DeckListRepository?
    let cardRepository: CardRepositoryProtocol?
    let correctionService: CardCorrectionService?

    @State private var viewModel = ImageSplitterViewModel()
    @State private var correctingIndex: Int?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var addMode = false
    /// Index of the box currently being resized (nil = none)
    @State private var resizingIndex: Int?
    /// Which corner/edge is being dragged
    @State private var dragEdge: DragEdge = .none
    @State private var dragStart: CGPoint = .zero
    /// Index of the card whose crop box is being adjusted in a sheet
    @State private var adjustingCropIndex: Int?

    private enum DragEdge { case none, topLeft, topRight, bottomLeft, bottomRight, move }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.sourceImage == nil {
                photoPickerView
            } else if viewModel.isDetecting {
                ProgressView("Detecting cards...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isIdentifying && viewModel.identifiedCards.isEmpty && GeminiVisionService.isActive {
                geminiProcessingView
            } else {
                splitPreviewView
            }
        }
        .onAppear {
            // Load initial embedding count
            if let store = correctionService?.embeddingStore {
                Task {
                    let count = await store.count
                    let unique = await store.uniqueCardCount
                    viewModel.embeddingCount = count
                    viewModel.embeddingUniqueCards = unique
                }
            }
        }
        .navigationTitle("Split Cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.sourceImage != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        viewModel.sourceImage = nil
                        selectedPhoto = nil
                        addMode = false
                    }
                }
            }
        }
        .alert("Saved!", isPresented: $viewModel.showSaveAlert) {
            Button("OK") {}
        } message: {
            Text("\(viewModel.selectedIndices.count) card image(s) saved to your photo library.")
        }
        .alert("Added!", isPresented: $viewModel.showAddedAlert) {
            Button("OK") {}
        } message: {
            Text("Cards added to your collection.")
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(viewModel.saveError ?? "")
        }
        .sheet(isPresented: .init(
            get: { correctingIndex != nil },
            set: { if !$0 { correctingIndex = nil } }
        )) {
            if let repo = cardRepository, let index = correctingIndex {
                CardCorrectionView(
                    repository: repo,
                    currentCard: viewModel.identifiedCards[index],
                    onCorrection: { correctedCard in
                        viewModel.correctCard(at: index, to: correctedCard, correctionService: correctionService)
                        correctingIndex = nil
                    }
                )
            }
        }
    }

    // MARK: - Gemini Processing View

    private var geminiProcessingView: some View {
        VStack(spacing: 20) {
            Spacer()

            if let sourceImage = viewModel.sourceImage {
                Image(decorative: sourceImage, scale: 1.0)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(MD3Theme.primary.opacity(0.3), lineWidth: 2)
                    )
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                if GeminiVisionService.isActive {
                    Text("Identifying cards with Gemini Vision...")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                    Text("Sending image for AI analysis")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                } else {
                    Text("Detecting cards...")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                }
            }

            Button {
                viewModel.cancelIdentification()
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.red, lineWidth: 1)
                    )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(MD3Theme.background)
    }

    // MARK: - Photo Picker

    private var photoPickerView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "scissors")
                .font(.system(size: 48))
                .foregroundStyle(MD3Theme.primary)
            Text("Split Card Photo")
                .font(MD3Typography.headlineSmall)
                .foregroundStyle(MD3Theme.onSurface)
            Text("Select a photo of cards to split them into individual images with prices.")
                .font(.subheadline)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                    Text("Choose Photo")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(MD3Theme.primary)
                .clipShape(Capsule())
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadPhoto(newValue) }
            }

            // Training data progress
            let count = TrainingDataCollector.shared.trainingDataCount()
            let target = 50
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(count >= target ? .green : MD3Theme.onSurfaceVariant)
                    Text("ML Training Data: \(count)/\(target) photos")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MD3Theme.onSurface)
                }
                ProgressView(value: Double(min(count, target)), total: Double(target))
                    .tint(count >= target ? .green : MD3Theme.primary)
                    .frame(width: 200)
                if count >= target {
                    Text("Ready to train! Run train_model.sh on Mac")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                } else {
                    Text("Scan \(target - count) more photos to train ML model")
                        .font(.system(size: 10))
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Split Preview

    private var splitPreviewView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let sourceImage = viewModel.sourceImage {
                    imageWithBoxes(sourceImage)
                        .padding(.horizontal, 16)
                }

                controlsSection

                // Scan results list (shows both identified and failed cards)
                if !viewModel.identifiedCards.isEmpty || !viewModel.debugLogs.isEmpty {
                    scanResultsList
                }

                // Card crops grid (only before any scan attempt)
                if !viewModel.detectedCards.isEmpty && viewModel.identifiedCards.isEmpty && viewModel.debugLogs.isEmpty {
                    detectedCardsGrid
                }

                // Action buttons
                actionButtons
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .padding(.top, 12)
        }
        .background(MD3Theme.background)
    }

    // MARK: - Image with Adjustable Boxes

    private func imageWithBoxes(_ image: CGImage) -> some View {
        let uiImage = UIImage(cgImage: image)
        return GeometryReader { geometry in
            let displayW = geometry.size.width
            let imgDisplayH = displayW * uiImage.size.height / uiImage.size.width

            ZStack(alignment: .topLeading) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if addMode {
                            let imgX = location.x / displayW * uiImage.size.width
                            let imgY = location.y / imgDisplayH * uiImage.size.height
                            viewModel.addManualRegion(at: CGPoint(x: imgX, y: imgY))
                            addMode = false  // Auto-exit add mode after adding one card
                        }
                    }

                ForEach(Array(viewModel.detectedCards.enumerated()), id: \.offset) { index, card in
                    let rect = card.rect
                    let x = rect.origin.x / uiImage.size.width * displayW
                    let y = rect.origin.y / uiImage.size.height * imgDisplayH
                    let w = rect.width / uiImage.size.width * displayW
                    let h = rect.height / uiImage.size.height * imgDisplayH

                    let isSelected = viewModel.selectedIndices.contains(index)

                    // Box (tap only — no drag gesture to avoid conflict with corner handles)
                    Rectangle()
                        .stroke(isSelected ? Color.green : Color.yellow.opacity(0.5), lineWidth: isSelected ? 2.5 : 1.5)
                        .background(isSelected ? Color.green.opacity(0.08) : Color.clear)
                        .frame(width: w, height: h)
                        .position(x: x + w / 2, y: y + h / 2)
                        .allowsHitTesting(!addMode)
                        .onTapGesture {
                            if isSelected {
                                viewModel.selectedIndices.remove(index)
                            } else {
                                viewModel.selectedIndices.insert(index)
                            }
                        }

                    // Resize handles (corners)
                    if isSelected && !addMode {
                        resizeHandle(index: index, corner: .bottomRight,
                                     x: x + w, y: y + h,
                                     uiImage: uiImage, displayW: displayW, imgDisplayH: imgDisplayH)
                        resizeHandle(index: index, corner: .topLeft,
                                     x: x, y: y,
                                     uiImage: uiImage, displayW: displayW, imgDisplayH: imgDisplayH)
                        resizeHandle(index: index, corner: .topRight,
                                     x: x + w, y: y,
                                     uiImage: uiImage, displayW: displayW, imgDisplayH: imgDisplayH)
                        resizeHandle(index: index, corner: .bottomLeft,
                                     x: x, y: y + h,
                                     uiImage: uiImage, displayW: displayW, imgDisplayH: imgDisplayH)
                    }

                    // Index label
                    if isSelected {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.green)
                            .clipShape(Circle())
                            .position(x: x + 14, y: y + 14)
                            .allowsHitTesting(false)
                    }
                }

                if addMode {
                    VStack {
                        Spacer()
                        Text("Tap on a card to add it")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.7))
                            .clipShape(Capsule())
                            .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(addMode ? Color.orange : Color.clear, lineWidth: 3)
            )
        }
        .aspectRatio(uiImage.size.width / uiImage.size.height, contentMode: .fit)
    }

    /// Corner resize handle — drag to resize the bounding box.
    /// Large hit area (44pt) for easy touch targeting.
    private func resizeHandle(
        index: Int, corner: DragEdge,
        x: CGFloat, y: CGFloat,
        uiImage: UIImage, displayW: CGFloat, imgDisplayH: CGFloat
    ) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.green, lineWidth: 3))
            .shadow(color: .black.opacity(0.3), radius: 2)
            .frame(width: 44, height: 44) // Large hit area
            .contentShape(Circle().scale(2))
            .position(x: x, y: y)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard index < viewModel.detectedCards.count else { return }
                        // Use the rect from drag START, not current (avoids cumulative drift)
                        if viewModel.dragStartRects[index] == nil {
                            viewModel.beginDrag(at: index)
                        }
                        guard let startRect = viewModel.dragStartRects[index] else { return }
                        let dx = value.translation.width / displayW * uiImage.size.width
                        let dy = value.translation.height / imgDisplayH * uiImage.size.height

                        var newRect = startRect
                        switch corner {
                        case .topLeft:
                            newRect = CGRect(
                                x: startRect.origin.x + dx,
                                y: startRect.origin.y + dy,
                                width: startRect.width - dx,
                                height: startRect.height - dy
                            )
                        case .topRight:
                            newRect = CGRect(
                                x: startRect.origin.x,
                                y: startRect.origin.y + dy,
                                width: startRect.width + dx,
                                height: startRect.height - dy
                            )
                        case .bottomLeft:
                            newRect = CGRect(
                                x: startRect.origin.x + dx,
                                y: startRect.origin.y,
                                width: startRect.width - dx,
                                height: startRect.height + dy
                            )
                        case .bottomRight:
                            newRect = CGRect(
                                x: startRect.origin.x,
                                y: startRect.origin.y,
                                width: startRect.width + dx,
                                height: startRect.height + dy
                            )
                        default: break
                        }
                        viewModel.updateRegion(at: index, newRect: newRect)
                    }
                    .onEnded { _ in
                        viewModel.dragStartRects.removeValue(forKey: index)
                    }
            )
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(viewModel.detectedCards.count) cards detected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
                Text("\(viewModel.selectedIndices.count) selected")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

            HStack(spacing: 12) {
                Button {
                    addMode.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: addMode ? "xmark.circle.fill" : "plus.circle")
                        Text(addMode ? "Done" : "Add Card")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(addMode ? .orange : MD3Theme.primary)
                }
                Spacer()
                // Training data counter
                if viewModel.embeddingCount > 0 {
                    Text("\(viewModel.embeddingUniqueCards) cards learned (\(viewModel.embeddingCount) samples)")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
                if viewModel.trainingDataCount > 0 {
                    Text("\(viewModel.trainingDataCount) training samples")
                        .font(.system(size: 10))
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }

            HStack(spacing: 16) {
                Button {
                    if viewModel.selectedIndices.count == viewModel.detectedCards.count {
                        viewModel.selectedIndices.removeAll()
                    } else {
                        viewModel.selectedIndices = Set(viewModel.detectedCards.indices)
                    }
                } label: {
                    Text(viewModel.selectedIndices.count == viewModel.detectedCards.count ? "Deselect All" : "Select All")
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Toggle(isOn: $viewModel.priceOverlayEnabled) {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle")
                        Text("Price Labels")
                    }
                    .font(.caption.weight(.semibold))
                }
                .toggleStyle(.switch)
                .fixedSize()
            }

            // Identify button (always visible, shows "Rescan" after first scan)
            if !viewModel.isIdentifying {
                let isRescan = !viewModel.identifiedCards.isEmpty
                Button {
                    viewModel.addedToCollection = false
                    viewModel.saveSuccess = false
                    Task { await viewModel.identifyCards() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isRescan ? "arrow.clockwise" : "sparkle.magnifyingglass")
                        Text(isRescan ? "Rescan Cards" : "Scan & Identify Cards")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(MD3Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if viewModel.isIdentifying, let progress = viewModel.identifyingProgress {
                ProgressView("Identifying \(progress.current)/\(progress.total)...",
                             value: Double(progress.current), total: Double(progress.total))
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Scan Results List

    private var scanResultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ML learning feedback banner
            if let feedback = viewModel.correctionFeedback {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(feedback)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MD3Theme.onSurface)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .transition(.opacity)
            }

            Text("Identified Cards")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MD3Theme.onSurface)
                .padding(.horizontal, 16)

            let identifiedPairs: [(index: Int, card: Card)] = viewModel.selectedIndices.sorted().compactMap { idx in
                guard let c = viewModel.identifiedCards[idx] else { return nil }
                return (index: idx, card: c)
            }
            let pagerCards = identifiedPairs.map(\.card)

            ForEach(viewModel.selectedIndices.sorted(), id: \.self) { index in
                if let card = viewModel.identifiedCards[index] {
                    HStack(spacing: 0) {
                        NavigationLink {
                            if let repo = cardRepository, let deckRepo = deckRepository {
                                let pos = identifiedPairs.firstIndex(where: { $0.index == index }) ?? 0
                                CardListPagerView(
                                    cards: pagerCards,
                                    initialIndex: pos,
                                    cardRepository: repo,
                                    deckRepository: deckRepo
                                )
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(decorative: viewModel.detectedCards[index].image, scale: 1.0)
                                    .resizable()
                                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
                                    .frame(height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(card.name)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(MD3Theme.onSurface)
                                            .lineLimit(1)
                                        if viewModel.geminiIdentified.contains(index) {
                                            Text("Gemini")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.blue)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(card.setNameWithYear)
                                        .font(.caption2)
                                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                                        .lineLimit(1)
                                }
                                Spacer()

                                // Quantity stepper
                                quantityStepper(for: index)

                                if let usd = card.prices.usd {
                                    Text("$\(usd)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(MD3Theme.primary)
                                        .monospacedDigit()
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
                            }
                            .padding(.vertical, 6)
                        }

                        if cardRepository != nil {
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
                            .padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                } else if let log = viewModel.debugLogs[index] {
                    // Show debug info for cards that failed identification
                    HStack(spacing: 12) {
                        Image(decorative: viewModel.detectedCards[index].image, scale: 1.0)
                            .resizable()
                            .aspectRatio(63.0 / 88.0, contentMode: .fit)
                            .frame(height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red, lineWidth: 1))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not identified")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red)
                            Text(log)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                                .lineLimit(3)
                        }
                        Spacer()

                        if cardRepository != nil {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Detected Cards Grid (before identification)

    private var detectedCardsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
            spacing: 10
        ) {
            ForEach(Array(viewModel.detectedCards.enumerated()), id: \.offset) { index, card in
                let isSelected = viewModel.selectedIndices.contains(index)
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        Image(decorative: card.image, scale: 1.0)
                            .resizable()
                            .aspectRatio(63.0 / 88.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
                            )
                            .opacity(isSelected ? 1.0 : 0.5)

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(isSelected ? .green : .gray)
                            .background(Circle().fill(.white).padding(2))
                            .offset(x: 4, y: -4)
                    }
                    .onTapGesture {
                        if isSelected { viewModel.selectedIndices.remove(index) }
                        else { viewModel.selectedIndices.insert(index) }
                    }
                    .onLongPressGesture {
                        adjustingCropIndex = index
                    }

                    Text("Hold to adjust")
                        .font(.system(size: 7))
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: Binding(
            get: { adjustingCropIndex != nil },
            set: { if !$0 { adjustingCropIndex = nil } }
        )) {
            if let index = adjustingCropIndex, let sourceImage = viewModel.sourceImage,
               index < viewModel.detectedCards.count {
                CropAdjustmentSheet(
                    sourceImage: sourceImage,
                    cardRect: viewModel.detectedCards[index].rect,
                    onUpdate: { newRect in
                        viewModel.updateRegion(at: index, newRect: newRect)
                    },
                    onDismiss: { adjustingCropIndex = nil }
                )
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Add to Collection
            if !viewModel.identifiedCards.isEmpty {
                Button {
                    viewModel.addToCollection()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.addedToCollection ? "checkmark.circle.fill" : "plus.rectangle.on.rectangle")
                        Text(viewModel.addedToCollection ? "Added to Collection" : "Add \(viewModel.totalCardQuantity) to Collection")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.addedToCollection ? Color.gray : Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.addedToCollection)
            }

            // Save to Photos
            Button {
                Task { await viewModel.saveSelectedCards() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: viewModel.saveSuccess ? "checkmark.circle.fill" : "square.and.arrow.down.on.square")
                    }
                    Text(viewModel.isSaving ? "Saving..." : viewModel.saveSuccess ? "Saved to Photos" : "Save \(viewModel.selectedIndices.count) Card(s) to Photos")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.selectedIndices.isEmpty || viewModel.isSaving || viewModel.saveSuccess ? Color.gray : MD3Theme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.selectedIndices.isEmpty || viewModel.isSaving || viewModel.saveSuccess)
        }
    }

    // MARK: - Quantity Stepper

    private func quantityStepper(for index: Int) -> some View {
        let qty = viewModel.quantities[index] ?? 1
        return HStack(spacing: 4) {
            Button {
                viewModel.setQuantity(qty - 1, for: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(qty > 1 ? MD3Theme.primary : Color.gray.opacity(0.4))
            }
            .disabled(qty <= 1)

            Text("\(qty)x")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(MD3Theme.onSurface)
                .monospacedDigit()
                .frame(minWidth: 28)

            Button {
                viewModel.setQuantity(qty + 1, for: index)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(qty < 20 ? MD3Theme.primary : Color.gray.opacity(0.4))
            }
            .disabled(qty >= 20)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return }
        viewModel = ImageSplitterViewModel(pipeline: pipeline, deckRepository: deckRepository)
        viewModel.setImage(cgImage)
        await viewModel.detect()
    }
}

// MARK: - Crop Adjustment Sheet

/// Full-screen sheet showing the source image zoomed to a card's region
/// with draggable corner handles for adjusting the crop box.
struct CropAdjustmentSheet: View {

    let sourceImage: CGImage
    let cardRect: CGRect
    let onUpdate: (CGRect) -> Void
    let onDismiss: () -> Void

    @State private var currentRect: CGRect
    @State private var dragStartRect: CGRect?
    @Environment(\.dismiss) private var dismiss

    init(sourceImage: CGImage, cardRect: CGRect, onUpdate: @escaping (CGRect) -> Void, onDismiss: @escaping () -> Void) {
        self.sourceImage = sourceImage
        self.cardRect = cardRect
        self.onUpdate = onUpdate
        self.onDismiss = onDismiss
        self._currentRect = State(initialValue: cardRect)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let uiImage = UIImage(cgImage: sourceImage)
                let displayW = geometry.size.width
                let imgDisplayH = displayW * uiImage.size.height / uiImage.size.width

                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .frame(width: displayW * 2, height: imgDisplayH * 2)

                            let scaleX = displayW * 2 / uiImage.size.width
                            let scaleY = imgDisplayH * 2 / uiImage.size.height
                            let x = currentRect.origin.x * scaleX
                            let y = currentRect.origin.y * scaleY
                            let w = currentRect.width * scaleX
                            let h = currentRect.height * scaleY

                            // Crop box
                            Rectangle()
                                .stroke(Color.green, lineWidth: 3)
                                .background(Color.green.opacity(0.1))
                                .frame(width: w, height: h)
                                .position(x: x + w / 2, y: y + h / 2)

                            // Corner handles
                            cropHandle(scaleX: scaleX, scaleY: scaleY, corner: .topLeft,
                                      handleX: x, handleY: y, imageSize: uiImage.size)
                            cropHandle(scaleX: scaleX, scaleY: scaleY, corner: .topRight,
                                      handleX: x + w, handleY: y, imageSize: uiImage.size)
                            cropHandle(scaleX: scaleX, scaleY: scaleY, corner: .bottomLeft,
                                      handleX: x, handleY: y + h, imageSize: uiImage.size)
                            cropHandle(scaleX: scaleX, scaleY: scaleY, corner: .bottomRight,
                                      handleX: x + w, handleY: y + h, imageSize: uiImage.size)
                        }
                    }
                }
            }
            .navigationTitle("Adjust Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onUpdate(currentRect)
                        dismiss()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") {
                        currentRect = cardRect
                    }
                }
            }
        }
    }

    private func cropHandle(scaleX: CGFloat, scaleY: CGFloat, corner: Corner,
                           handleX: CGFloat, handleY: CGFloat, imageSize: CGSize) -> some View {
        Circle()
            .fill(Color.green)
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .position(x: handleX, y: handleY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartRect == nil { dragStartRect = currentRect }
                        guard let start = dragStartRect else { return }
                        let dx = value.translation.width / scaleX
                        let dy = value.translation.height / scaleY

                        var newRect = start
                        switch corner {
                        case .topLeft:
                            newRect.origin.x = max(0, start.origin.x + dx)
                            newRect.origin.y = max(0, start.origin.y + dy)
                            newRect.size.width = max(20, start.width - dx)
                            newRect.size.height = max(20, start.height - dy)
                        case .topRight:
                            newRect.origin.y = max(0, start.origin.y + dy)
                            newRect.size.width = min(imageSize.width - start.origin.x, max(20, start.width + dx))
                            newRect.size.height = max(20, start.height - dy)
                        case .bottomLeft:
                            newRect.origin.x = max(0, start.origin.x + dx)
                            newRect.size.width = max(20, start.width - dx)
                            newRect.size.height = min(imageSize.height - start.origin.y, max(20, start.height + dy))
                        case .bottomRight:
                            newRect.size.width = min(imageSize.width - start.origin.x, max(20, start.width + dx))
                            newRect.size.height = min(imageSize.height - start.origin.y, max(20, start.height + dy))
                        }
                        currentRect = newRect
                    }
                    .onEnded { _ in dragStartRect = nil }
            )
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
}
