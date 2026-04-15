import SwiftUI

/// Sheet to manually add a card to the collection. Mirrors the existing
/// `AddCardToDeckSheet` search-pattern: type a name, see matching printings,
/// pick one, set quantity, save.
struct AddToCollectionSheet: View {

    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol
    let onAdded: () -> Void

    @State private var query: String = ""
    @State private var results: [Card] = []
    @State private var selectedCard: Card?
    @State private var quantity: Int = 1
    @State private var foilQuantity: Int = 0
    @State private var isSearching: Bool = false
    @State private var didAdd: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    TextField("Card name", text: $query)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                        .onChange(of: query) { _, _ in
                            Task { await search() }
                        }
                }

                if isSearching {
                    Section {
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text("Searching…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let selected = selectedCard {
                    Section("Selected printing") {
                        printingRow(selected, isSelected: true)
                    }
                    Section("Quantity") {
                        Stepper("\(quantity) total", value: $quantity, in: 1...99)
                        Stepper("\(foilQuantity) foil", value: $foilQuantity, in: 0...quantity)
                    }
                    Section {
                        Button("Add to Collection") { add(selected) }
                            .disabled(quantity < 1)
                    }
                } else if !results.isEmpty {
                    Section("Pick a printing") {
                        ForEach(results) { card in
                            Button {
                                selectedCard = card
                            } label: {
                                printingRow(card, isSelected: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if didAdd {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private func printingRow(_ card: Card, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("\(card.setNameWithYear) · #\(card.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let usdString = card.prices.usd, let usd = Double(usdString) {
                Text("$\(MoneyFormat.compact(usd))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
        }
    }

    private func search() async {
        // Reset selection when query changes substantially
        selectedCard = nil

        let trimmed = query.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        // Get all printings of the card name. Sorted oldest-first so vintage
        // printings appear first (matches Classic Decks behavior).
        let printings = (try? await cardRepository.findAllPrintings(name: trimmed)) ?? []
        results = printings.sorted { (a, b) -> Bool in
            let aDate = a.releasedAt ?? "9999"
            let bDate = b.releasedAt ?? "9999"
            return aDate < bDate
        }
    }

    private func add(_ card: Card) {
        _ = try? deckRepository.addToCollection(
            card: card,
            quantity: quantity,
            foilQuantity: foilQuantity
        )
        didAdd = true
        onAdded()
        // Reset for the next add
        selectedCard = nil
        results = []
        query = ""
        quantity = 1
        foilQuantity = 0
    }
}
