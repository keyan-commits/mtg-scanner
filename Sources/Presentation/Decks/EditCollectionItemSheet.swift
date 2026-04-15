import SwiftUI

/// Small sheet to edit or remove a single CollectionItem.
struct EditCollectionItemSheet: View {

    let item: CollectionItem
    let deckRepository: DeckListRepository
    let onChanged: () -> Void

    @State private var quantity: Int = 1
    @State private var foilQuantity: Int = 0
    @State private var notes: String = ""
    @State private var showDeleteConfirm: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.cardName)
                        .font(.headline)
                    Text("\(item.setName) · #\(item.collectorNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Quantity") {
                    Stepper("\(quantity) total", value: $quantity, in: 0...99)
                    Stepper("\(foilQuantity) foil", value: $foilQuantity, in: 0...max(quantity, 0))
                }

                Section("Notes") {
                    TextField("Condition, where it's stored, etc.", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete from collection", systemImage: "trash")
                    }
                }

                Section {
                    Text("Setting quantity to 0 also removes the entry.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                }
            }
            .alert("Delete this entry?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    try? deckRepository.deleteCollectionItem(item)
                    onChanged()
                    dismiss()
                }
            }
        }
        .onAppear {
            quantity = item.quantity
            foilQuantity = item.foilQuantity
            notes = item.notes ?? ""
        }
    }

    private func save() {
        // Notes go directly through SwiftData since the repo doesn't expose
        // a notes setter — the @Model object is mutable and attached to the
        // shared context, so this is safe.
        item.notes = notes.isEmpty ? nil : notes
        try? deckRepository.setCollectionQuantity(
            item,
            quantity: quantity,
            foilQuantity: foilQuantity
        )
        onChanged()
        dismiss()
    }
}
