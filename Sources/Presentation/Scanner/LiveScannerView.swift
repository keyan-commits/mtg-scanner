import SwiftUI
import AudioToolbox

/// Live camera view for scanning MTG cards. Identifies cards directly from video
/// frame OCR + DB lookup — no photo capture needed. Instant results.
struct LiveScannerView: View {

    let pipeline: CardIdentificationPipelineProtocol
    let correctionService: CardCorrectionService?
    let repository: CardRepositoryProtocol?
    let deckRepository: DeckListRepository?
    var onCardsScanned: (([Card]) -> Void)?

    @StateObject private var cameraManager = CameraManager()
    @State private var scannedCards: [Card] = []
    /// Quantity per scanned card, keyed by scryfallID. Re-scanning the same
    /// card increments instead of adding a duplicate row, matching Batch /
    /// Split behavior.
    @State private var scannedQuantities: [String: Int] = [:]
    @State private var lastIdentified: Card?
    @State private var isLookingUp = false
    @State private var showScannedList = false
    @State private var addedToCollection: Set<String> = []
    @State private var didAddAll: Bool = false
    /// scryfallID of the card whose Fix sheet is open, nil otherwise.
    @State private var correctingScryfallID: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                CameraPreviewView(session: cameraManager.session)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        // Convert SwiftUI point to AVFoundation's normalized
                        // (0,0)=top-left coordinate space and request a
                        // momentary autofocus + autoexposure at that point.
                        let normalized = CGPoint(
                            x: max(0, min(1, location.x / max(1, geometry.size.width))),
                            y: max(0, min(1, location.y / max(1, geometry.size.height)))
                        )
                        cameraManager.focus(at: normalized)
                    }
            }
            .ignoresSafeArea()

            // Detection overlay
            if let quad = cameraManager.detectedQuad {
                GeometryReader { geometry in
                    quadOverlay(quad: quad, in: geometry.size)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack {
                // Real-time card name from frame OCR
                if let name = cameraManager.recognizedCardName, lastIdentified == nil {
                    Text(name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 60)
                }

                Spacer()

                // Identified card banner
                if let card = lastIdentified {
                    identifiedBanner(card)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Status text
                if lastIdentified == nil {
                    Text(statusText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                }

                // Scanned cards count
                if !scannedCards.isEmpty {
                    Button {
                        showScannedList = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.stack.fill")
                            Text("\(totalScannedCount) scanned")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .clipShape(Capsule())
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lastIdentified?.id)
        .onAppear {
            cameraManager.configure()
            cameraManager.start()
        }
        .onDisappear {
            cameraManager.stop()
            if !scannedCards.isEmpty {
                onCardsScanned?(scannedCards)
            }
        }
        .onChange(of: cameraManager.confirmedCardName) { _, confirmedName in
            guard let name = confirmedName, !isLookingUp else { return }
            Task {
                await lookupCard(name: name)
            }
        }
        .onChange(of: cameraManager.pendingArtImage) { _, art in
            // Visual fallback fires when frame OCR has stalled. We hand the
            // upright art crop to the photo pipeline's visual-only matchers
            // (FeaturePrint cache, embedding store, pHash). Lets us identify
            // cards whose text is too blurry to read.
            guard let art, !isLookingUp, lastIdentified == nil else { return }
            Task {
                await lookupCardByArt(art)
                cameraManager.clearPendingArtImage()
            }
        }
        .sheet(isPresented: $showScannedList) {
            scannedListSheet
        }
        .sheet(item: Binding(
            get: { correctingScryfallID.map(CorrectionTarget.init(scryfallID:)) },
            set: { correctingScryfallID = $0?.scryfallID }
        )) { target in
            if let repo = repository,
               let card = scannedCards.first(where: { $0.scryfallID == target.scryfallID }) {
                CardCorrectionView(
                    repository: repo,
                    currentCard: card,
                    onCorrection: { newCard in
                        replaceCard(scryfallID: target.scryfallID, with: newCard)
                        correctingScryfallID = nil
                    }
                )
            }
        }
        .navigationTitle("Live Scan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct CorrectionTarget: Identifiable {
        let scryfallID: String
        var id: String { scryfallID }
    }

    // MARK: - Quad Overlay

    private func quadOverlay(quad: [CGPoint], in size: CGSize) -> some View {
        Path { path in
            let points = quad.map { pt in
                CGPoint(x: pt.x * size.width, y: (1 - pt.y) * size.height)
            }
            guard points.count == 4 else { return }
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            path.closeSubpath()
        }
        .stroke(overlayColor, lineWidth: 3)
    }

    private var overlayColor: Color {
        switch cameraManager.scanState {
        case .confirmed:
            return .blue
        case .reading:
            return .yellow
        default:
            return .green
        }
    }

    // MARK: - Status Text

    private var statusText: String {
        if isLookingUp { return "Identifying..." }
        switch cameraManager.scanState {
        case .idle, .detecting:
            return "Point at a card"
        case .reading:
            return "Reading..."
        case .confirmed:
            return "Identifying..."
        }
    }

    // MARK: - Identified Banner

    private func identifiedBanner(_ card: Card) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(card.set.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            // Quick "add to collection" on the banner itself
            if deckRepository != nil {
                Button {
                    quickAddToCollection(card)
                } label: {
                    Image(systemName: addedToCollection.contains(card.scryfallID)
                          ? "checkmark.circle.fill"
                          : "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(addedToCollection.contains(card.scryfallID) ? .green : .cyan)
                }
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
        .padding(16)
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func quickAddToCollection(_ card: Card) {
        guard let deckRepository,
              !addedToCollection.contains(card.scryfallID) else { return }
        let qty = scannedQuantities[card.scryfallID] ?? 1
        if let _ = try? deckRepository.addToCollection(card: card, quantity: qty) {
            addedToCollection.insert(card.scryfallID)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    // MARK: - Scanned Cards List

    private var totalScannedCount: Int {
        scannedCards.reduce(0) { $0 + (scannedQuantities[$1.scryfallID] ?? 1) }
    }

    private var scannedListSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(scannedCards) { card in
                    scannedRow(for: card)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listStyle(.plain)

                // "Add All to Collection" footer
                if deckRepository != nil && !scannedCards.isEmpty {
                    VStack(spacing: 8) {
                        Divider()
                        if didAddAll || scannedCards.allSatisfy({ addedToCollection.contains($0.scryfallID) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("All \(totalScannedCount) added")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.green)
                            }
                            .padding(.vertical, 8)
                        } else {
                            let unaddedQty = scannedCards
                                .filter { !addedToCollection.contains($0.scryfallID) }
                                .reduce(0) { $0 + (scannedQuantities[$1.scryfallID] ?? 1) }
                            Button {
                                addAllScannedToCollection()
                            } label: {
                                Label("Add All \(unaddedQty) to Collection", systemImage: "rectangle.stack.fill.badge.plus")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Scanned (\(totalScannedCount))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showScannedList = false }
                }
            }
        }
    }

    @ViewBuilder
    private func scannedRow(for card: Card) -> some View {
        let qty = scannedQuantities[card.scryfallID] ?? 1
        HStack(spacing: 8) {
            CachedAsyncImage(url: card.preferredImageURL(.small)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
            }
            .frame(width: 36, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                Text("\(card.set.name) #\(card.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer()

            ScannedCardQuantityStepper(
                quantity: qty,
                onDecrement: { setQuantity(qty - 1, for: card.scryfallID) },
                onIncrement: { setQuantity(qty + 1, for: card.scryfallID) }
            )

            if let usd = card.prices.usd {
                Text("$\(usd)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MD3Theme.primary)
                    .monospacedDigit()
            }

            if addedToCollection.contains(card.scryfallID) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            if repository != nil {
                Button {
                    correctingScryfallID = card.scryfallID
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
                .buttonStyle(.plain)
            }
        }
    }

    private func setQuantity(_ newQty: Int, for scryfallID: String) {
        let clamped = max(1, min(20, newQty))
        scannedQuantities[scryfallID] = clamped
    }

    private func replaceCard(scryfallID: String, with newCard: Card) {
        guard let idx = scannedCards.firstIndex(where: { $0.scryfallID == scryfallID }) else { return }
        let oldQty = scannedQuantities[scryfallID] ?? 1
        let wasAdded = addedToCollection.contains(scryfallID)

        // If the corrected card is already elsewhere in the list, merge into
        // that entry rather than producing two rows for the same scryfallID.
        if let dupIdx = scannedCards.firstIndex(where: { $0.scryfallID == newCard.scryfallID }), dupIdx != idx {
            scannedQuantities[newCard.scryfallID, default: 1] += oldQty
            scannedCards.remove(at: idx)
            scannedQuantities.removeValue(forKey: scryfallID)
            addedToCollection.remove(scryfallID)
            return
        }

        scannedCards[idx] = newCard
        scannedQuantities.removeValue(forKey: scryfallID)
        scannedQuantities[newCard.scryfallID] = oldQty
        if wasAdded {
            addedToCollection.remove(scryfallID)
            addedToCollection.insert(newCard.scryfallID)
        }
    }

    private func addAllScannedToCollection() {
        guard let deckRepository else { return }
        var addedAny = false
        for card in scannedCards where !addedToCollection.contains(card.scryfallID) {
            let qty = scannedQuantities[card.scryfallID] ?? 1
            if let _ = try? deckRepository.addToCollection(card: card, quantity: qty) {
                addedToCollection.insert(card.scryfallID)
                addedAny = true
            }
        }
        if addedAny {
            didAddAll = true
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    // MARK: - Quick DB Lookup (no photo capture needed)

    private func lookupCard(name: String) async {
        isLookingUp = true

        // Quick DB lookup by name — instant, no pipeline needed
        if let repo = repository {
            // Try exact match first, then fuzzy
            if let card = try? await repo.identifyCard(name: name) {
                addCard(card)
                isLookingUp = false
                return
            }
            // Try finding printings (handles case sensitivity)
            if let printings = try? await repo.findAllPrintings(name: name),
               let card = printings.first {
                addCard(card)
                isLookingUp = false
                return
            }
        }

        // Card not found — reset and try again
        isLookingUp = false
        cameraManager.reset()
    }

    /// Visual fallback used when frame OCR couldn't confirm a card name.
    /// Hands the cropped art to the photo pipeline's visual-only matchers
    /// (FeaturePrint, embedding store, pHash) — same code that identifies
    /// blurry photo captures. If a match comes back we feed it through the
    /// same `addCard` path the OCR-confirmed flow uses.
    private func lookupCardByArt(_ art: CGImage) async {
        guard !isLookingUp else { return }
        isLookingUp = true
        defer { isLookingUp = false }

        if let card = await pipeline.identifyCropped(cardImage: art, visualOnly: true) {
            print("[LiveScan] Visual fallback identified: \(card.name)")
            addCard(card)
        } else {
            print("[LiveScan] Visual fallback returned no match")
        }
    }

    private func addCard(_ card: Card) {
        lastIdentified = card

        // Re-scanning the same card increments quantity instead of adding a
        // duplicate row — matches Batch / Split behavior.
        if scannedCards.contains(where: { $0.scryfallID == card.scryfallID }) {
            scannedQuantities[card.scryfallID, default: 1] += 1
        } else {
            scannedCards.append(card)
            scannedQuantities[card.scryfallID] = 1
        }
        playCaptureFeedback()

        // Banner fades after 1.5s for UX feedback. The scanner itself stays
        // locked until the user physically removes the card from frame —
        // CameraManager's empty-frame counter handles that automatically.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            lastIdentified = nil
        }
    }

    /// Confirms a successful capture with a haptic (always fires) and the
    /// system "Tink" sound (only audible when the ringer switch is on, like
    /// the camera shutter). Keeps the user aware of captures without forcing
    /// them to look at the screen on a scanner stand.
    private func playCaptureFeedback() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1057)
    }
}
