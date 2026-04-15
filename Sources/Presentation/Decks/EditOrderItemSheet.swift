import SwiftUI

/// Small sheet for fixing the price / store / currency / notes / URL on a
/// group of `PurchaseItem` copies that share an Order. Edits cascade to
/// every item passed in (so if you fix a typo on the per-card price for
/// "4 Contagion", all 4 copies get the new value).
///
/// Unlike `MarkOrderedSheet`, this view does NOT change the item's status
/// — it's strictly for fixing typos / metadata after the fact.
struct EditOrderItemSheet: View {

    let items: [PurchaseItem]
    let repository: DeckListRepository
    let onDone: () -> Void

    @State private var store: String = ""
    @State private var purchaseURL: String = ""
    @State private var pricePaidText: String = ""
    @State private var currency: String = "USD"
    @State private var notes: String = ""

    @Environment(\.dismiss) private var dismiss

    private let currencies = ["USD", "PHP", "JPY", "EUR", "GBP", "CAD", "AUD"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let first = items.first {
                        Text(first.cardName)
                            .font(.headline)
                        Text("\(first.setName) · #\(first.collectorNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(items.count) cop\(items.count == 1 ? "y" : "ies") will be updated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Store") {
                    TextField("Store name", text: $store)
                        .autocorrectionDisabled()
                    TextField("Order URL (optional)", text: $purchaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: purchaseURL) { _, newValue in
                            if store.isEmpty,
                               let detected = PurchaseItem.detectStore(from: newValue) {
                                store = detected
                            }
                        }
                }

                Section("Price per copy") {
                    HStack {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencies, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        TextField("0.00", text: $pricePaidText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Notes") {
                    TextField("Tracking number, condition, seller…", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Text("These values overwrite the per-copy fields on every copy. Status (Needed/Ordered/Arrived) is not changed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Copies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear { populate() }
    }

    private func populate() {
        guard let first = items.first else { return }
        store = first.store ?? ""
        purchaseURL = first.purchaseURL ?? ""
        pricePaidText = first.pricePaid.map { String(format: "%.2f", $0) } ?? ""
        currency = first.currency ?? "USD"
        notes = first.notes ?? ""
    }

    private func save() {
        let price = Double(pricePaidText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ""))
        for item in items {
            try? repository.updateItem(
                item,
                store: store,
                purchaseURL: purchaseURL,
                pricePaid: price,
                currency: currency,
                notes: notes
            )
        }
        onDone()
        dismiss()
    }
}
