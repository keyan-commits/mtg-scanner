import SwiftUI

/// Sheet that lists all printings of a card name and lets the user pick one.
/// Used from the import-results "wrong set" flow.
struct PickPrintingSheet: View {

    let cardName: String
    let quantity: Int
    let cardRepository: CardRepositoryProtocol
    let onPicked: (Card) -> Void

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
                            onPicked(printing)
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
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("\(quantity)× \(cardName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let all = (try? await cardRepository.findAllPrintings(name: cardName)) ?? []
        printings = all.sorted { ($0.releasedAt ?? "") > ($1.releasedAt ?? "") }
    }
}
