import SwiftUI

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
    @State private var lastIdentified: Card?
    @State private var isLookingUp = false
    @State private var showScannedList = false
    @State private var addedToCollection: Set<String> = []
    @State private var didAddAll: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            // Detection overlay
            if let quad = cameraManager.detectedQuad {
                GeometryReader { geometry in
                    quadOverlay(quad: quad, in: geometry.size)
                }
                .ignoresSafeArea()
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
                            Text("\(scannedCards.count) scanned")
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
        .sheet(isPresented: $showScannedList) {
            scannedListSheet
        }
        .navigationTitle("Live Scan")
        .navigationBarTitleDisplayMode(.inline)
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
        if let _ = try? deckRepository.addToCollection(card: card) {
            addedToCollection.insert(card.scryfallID)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    // MARK: - Scanned Cards List

    private var scannedListSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(scannedCards) { card in
                    HStack {
                        Text(card.name)
                            .font(.body)
                        Spacer()
                        if addedToCollection.contains(card.scryfallID) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                        Text(card.set.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // "Add All to Collection" footer
                if deckRepository != nil && !scannedCards.isEmpty {
                    VStack(spacing: 8) {
                        Divider()
                        if didAddAll || scannedCards.allSatisfy({ addedToCollection.contains($0.scryfallID) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("All \(scannedCards.count) added")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.green)
                            }
                            .padding(.vertical, 8)
                        } else {
                            let unadded = scannedCards.filter { !addedToCollection.contains($0.scryfallID) }
                            Button {
                                addAllScannedToCollection()
                            } label: {
                                Label("Add All \(unadded.count) to Collection", systemImage: "rectangle.stack.fill.badge.plus")
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
            .navigationTitle("Scanned (\(scannedCards.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showScannedList = false }
                }
            }
        }
    }

    private func addAllScannedToCollection() {
        guard let deckRepository else { return }
        var count = 0
        for card in scannedCards where !addedToCollection.contains(card.scryfallID) {
            if let _ = try? deckRepository.addToCollection(card: card) {
                addedToCollection.insert(card.scryfallID)
                count += 1
            }
        }
        if count > 0 {
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

    private func addCard(_ card: Card) {
        lastIdentified = card
        scannedCards.append(card)

        // Auto-reset after 1.5 seconds
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            lastIdentified = nil
            cameraManager.reset()
        }
    }
}
