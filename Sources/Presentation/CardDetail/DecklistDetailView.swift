import SwiftUI

/// Displays a full decklist fetched from MTGTop8, grouped into mainboard and sideboard.
struct DecklistDetailView: View {

    let deckID: String
    let deckName: String
    let player: String

    @State private var decklist: MTGTop8Decklist?
    @State private var isLoading = true
    @State private var error: String?

    @Environment(\.openURL) private var openURL

    private let service: MTGTop8ServiceProtocol

    init(deckID: String, deckName: String, player: String, service: MTGTop8ServiceProtocol = MTGTop8Service()) {
        self.deckID = deckID
        self.deckName = deckName
        self.player = player
        self.service = service
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading decklist...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(MD3Theme.error)
                    Text(error)
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let decklist {
                decklistContent(decklist)
            }
        }
        .navigationTitle(deckName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        copyDecklist()
                    } label: {
                        Label("Copy Decklist", systemImage: "doc.on.doc")
                    }
                    Button {
                        openOnMTGTop8()
                    } label: {
                        Label("View on MTGTop8", systemImage: "safari")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .background(MD3Theme.background)
        .task {
            await loadDecklist()
        }
    }

    // MARK: - Decklist Content

    private func decklistContent(_ decklist: MTGTop8Decklist) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                if !player.isEmpty {
                    Text("by \(player)")
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .padding(.horizontal, 16)
                }

                // Summary
                let mainCount = decklist.mainboard.reduce(0) { $0 + $1.quantity }
                let sideCount = decklist.sideboard.reduce(0) { $0 + $1.quantity }
                HStack(spacing: 16) {
                    label("Maindeck", count: mainCount)
                    label("Sideboard", count: sideCount)
                    Spacer()
                }
                .padding(.horizontal, 16)

                // Mainboard
                MD3Card {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionHeader("Maindeck (\(mainCount))")

                        ForEach(decklist.mainboard) { entry in
                            cardRow(entry)
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 16)

                // Sideboard
                if !decklist.sideboard.isEmpty {
                    MD3Card {
                        VStack(alignment: .leading, spacing: 2) {
                            sectionHeader("Sideboard (\(sideCount))")

                            ForEach(decklist.sideboard) { entry in
                                cardRow(entry)
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Components

    private func label(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(MD3Typography.labelMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Text("\(count)")
                .font(MD3Typography.labelMedium)
                .foregroundStyle(MD3Theme.onPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(MD3Theme.primary)
                .clipShape(Capsule())
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(MD3Typography.titleSmall)
            .foregroundStyle(MD3Theme.onSurface)
            .padding(.bottom, 8)
    }

    private func cardRow(_ entry: MTGTop8DecklistEntry) -> some View {
        HStack(spacing: 8) {
            Text("\(entry.quantity)")
                .font(MD3Typography.bodyMedium.monospaced())
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .frame(width: 20, alignment: .trailing)

            Text(entry.cardName)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurface)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func copyDecklist() {
        guard let decklist else { return }
        var text = ""
        for entry in decklist.mainboard {
            text += "\(entry.quantity) \(entry.cardName)\n"
        }
        if !decklist.sideboard.isEmpty {
            text += "\nSideboard\n"
            for entry in decklist.sideboard {
                text += "\(entry.quantity) \(entry.cardName)\n"
            }
        }
        UIPasteboard.general.string = text
    }

    private func openOnMTGTop8() {
        if let url = URL(string: "https://mtgtop8.com/event?d=\(deckID)") {
            openURL(url)
        }
    }

    // MARK: - Data Loading

    private func loadDecklist() async {
        isLoading = true
        do {
            decklist = try await service.fetchDecklist(deckID: deckID)
            error = nil
        } catch {
            self.error = "Could not load decklist"
        }
        isLoading = false
    }
}
