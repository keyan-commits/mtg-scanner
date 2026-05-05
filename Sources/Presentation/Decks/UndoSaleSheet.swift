import SwiftUI

/// Sheet for reversing a sale that was recorded by mistake or fell
/// through. Mirrors RecordSaleSheet's shape (finish picker + quantity
/// stepper) but in reverse: copies come back to owned, the sold
/// ledger gets decremented, and the user can opt-in to re-list at the
/// same time.
struct UndoSaleSheet: View {
    let item: CollectionItem
    let deckRepository: DeckListRepository
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isFoil: Bool = false
    @State private var qty: Int = 1
    @State private var relist: Bool = false
    @State private var didLoad = false

    private var maxFoil: Int { item.soldFoilQuantity }
    private var maxNonfoil: Int { item.soldNonfoilQuantity }
    private var canUndoFoil: Bool { maxFoil > 0 }
    private var canUndoNonfoil: Bool { maxNonfoil > 0 }
    private var maxAvailable: Int { isFoil ? maxFoil : maxNonfoil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.cardName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("\(item.setName) · #\(item.collectorNumber)")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                    .padding(.vertical, 2)
                }

                if canUndoFoil && canUndoNonfoil {
                    Section("Finish to restore") {
                        Picker("Finish", selection: $isFoil) {
                            Text("Nonfoil (\(maxNonfoil) sold)").tag(false)
                            Text("Foil (\(maxFoil) sold)").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Copies to restore") {
                    Stepper(value: $qty, in: 1...max(maxAvailable, 1)) {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text("\(qty) of \(maxAvailable) sold")
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                    }
                }

                Section {
                    Toggle("Re-list these copies for sale", isOn: $relist)
                } footer: {
                    Text(relist
                         ? "Copies will go back to the Listed tab using the existing asking price."
                         : "Copies will return to your collection only — not re-listed.")
                        .font(.caption2)
                }
            }
            .navigationTitle("Undo sale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Undo") { performUndo() }
                        .disabled(maxAvailable == 0)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            // Default to whichever finish has sold copies (foil if it's
            // the only one). One-tap for the common single-finish case.
            isFoil = canUndoFoil && !canUndoNonfoil
            qty = max(1, min(qty, maxAvailable))
        }
        .onChange(of: isFoil) { (_: Bool, _: Bool) in
            qty = max(1, min(qty, maxAvailable))
        }
    }

    private func performUndo() {
        try? deckRepository.undoSale(item, isFoil: isFoil, quantity: qty, relist: relist)
        onClose()
        dismiss()
    }
}
