import SwiftUI

/// Sheet shown when adding a card to a deck. Lets the user pick an existing
/// deck or create a new one inline. Tracks quantity.
struct AddToDeckSheet: View {

    let card: Card
    let repository: DeckListRepository
    let onAdded: () -> Void

    @State private var decks: [DeckList] = []
    @State private var quantity: Int = 4
    @State private var newDeckName: String = ""
    @State private var showingNewDeck: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(card.name)
                        .font(.headline)
                    Text("\(card.setNameWithYear) #\(card.collectorNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Quantity") {
                    Stepper("\(quantity)", value: $quantity, in: 1...99)
                }

                Section("Add to") {
                    if decks.isEmpty {
                        Text("No decks yet — create one below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(decks) { deck in
                            Button {
                                addTo(deck)
                            } label: {
                                HStack {
                                    Text(deck.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(deck.items.count) cards")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Or create a new deck") {
                    if showingNewDeck {
                        TextField("Deck name", text: $newDeckName)
                        Button("Create & Add") {
                            createAndAdd()
                        }
                        .disabled(newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button {
                            showingNewDeck = true
                        } label: {
                            Label("New Deck", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle("Add to Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            decks = (try? repository.fetchAllDecks()) ?? []
        }
    }

    private func addTo(_ deck: DeckList) {
        _ = try? repository.addItem(card: card, quantity: quantity, to: deck)
        onAdded()
        dismiss()
    }

    private func createAndAdd() {
        let trimmed = newDeckName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let deck = try? repository.createDeck(name: trimmed) else { return }
        addTo(deck)
    }
}
