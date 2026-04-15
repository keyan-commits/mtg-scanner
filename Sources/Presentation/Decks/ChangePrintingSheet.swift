import SwiftUI

/// Sheet showing all printings of a card name. Tapping one updates the
/// PurchaseItem to point to the chosen printing.
struct ChangePrintingSheet: View {

    let item: PurchaseItem
    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol
    let onChanged: () -> Void
    /// When set, the chosen printing is applied to every item in this array
    /// instead of just `item`. Use this to retag all copies of a card at once.
    var applyToAll: [PurchaseItem]? = nil

    @State private var printings: [Card] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading printings…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if printings.isEmpty {
                    Text("No printings found")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(printings) { printing in
                        Button {
                            apply(printing)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(printing.set.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        Text("#\(printing.collectorNumber)")
                                        if let released = printing.releasedAt {
                                            Text(String(released.prefix(4)))
                                        }
                                        if let artist = printing.artist {
                                            Text("• \(artist)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if printing.scryfallID == item.scryfallID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(item.cardName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await cardRepository.findAllPrintings(name: item.cardName)) ?? []
        // Sort by release date descending so newest printings appear first
        printings = all.sorted { ($0.releasedAt ?? "") > ($1.releasedAt ?? "") }
    }

    private func apply(_ card: Card) {
        if let all = applyToAll, !all.isEmpty {
            for target in all {
                try? deckRepository.changePrinting(target, to: card)
            }
        } else {
            try? deckRepository.changePrinting(item, to: card)
        }
        onChanged()
        dismiss()
    }
}
