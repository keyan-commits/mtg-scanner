import SwiftUI

/// Sheet to edit an existing Order's header fields. Mirrors the header
/// portion of `MarkOrderReceivedSheet` but doesn't touch the items list.
struct EditOrderSheet: View {

    let order: Order
    let repository: DeckListRepository
    let onSaved: () -> Void

    @State private var store: String = ""
    @State private var currency: String = "USD"
    @State private var orderedAt: Date = Date()
    @State private var hasETA: Bool = false
    @State private var eta: Date = Date()
    @State private var purchaseURL: String = ""
    @State private var totalDueText: String = ""
    @State private var notes: String = ""

    @Environment(\.dismiss) private var dismiss

    private let currencies = ["USD", "PHP", "JPY", "EUR", "GBP", "CAD", "AUD"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Order Info") {
                    TextField("Store name", text: $store)
                        .autocorrectionDisabled()
                    Picker("Currency", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    DatePicker("Ordered", selection: $orderedAt, displayedComponents: .date)
                    Toggle("Has ETA", isOn: $hasETA)
                    if hasETA {
                        DatePicker("ETA", selection: $eta, displayedComponents: .date)
                    }
                    TextField("Total due (optional)", text: $totalDueText)
                        .keyboardType(.decimalPad)
                    TextField("Order URL (optional)", text: $purchaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Text("Editing only updates the order header. The card items in this order are not changed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(store.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { populateFromOrder() }
    }

    private func populateFromOrder() {
        store = order.store
        currency = order.currency
        orderedAt = order.orderedAt
        if let existingETA = order.eta {
            hasETA = true
            eta = existingETA
        } else {
            hasETA = false
            eta = Date().addingTimeInterval(60 * 60 * 24 * 14)
        }
        purchaseURL = order.purchaseURL ?? ""
        totalDueText = order.totalDue.map { $0.rounded() == $0 ? String(Int($0)) : String(format: "%.2f", $0) } ?? ""
        notes = order.notes ?? ""
    }

    private func save() {
        let total = Double(totalDueText.replacingOccurrences(of: ",", with: "."))
        try? repository.updateOrder(
            order,
            store: store.trimmingCharacters(in: .whitespaces),
            orderedAt: orderedAt,
            eta: hasETA ? eta : nil,
            purchaseURL: purchaseURL.isEmpty ? nil : purchaseURL,
            notes: notes.isEmpty ? nil : notes,
            currency: currency,
            totalDue: total
        )
        onSaved()
        dismiss()
    }
}
