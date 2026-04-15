import SwiftUI

/// Sheet for entering purchase details when marking a card as ordered.
/// All fields are optional. Detects store name from pasted URLs.
struct MarkOrderedSheet: View {

    let item: PurchaseItem
    let repository: DeckListRepository
    let onDone: () -> Void

    @State private var store: String = ""
    @State private var purchaseURL: String = ""
    @State private var pricePaidText: String = ""
    @State private var currency: String = "USD"
    @State private var notes: String = ""
    @State private var recentStores: [String] = []

    private let currencies = ["USD", "PHP", "JPY", "EUR", "GBP", "CAD", "AUD"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.cardName)
                        .font(.headline)
                    Text("\(item.setName) #\(item.collectorNumber) • Qty \(item.quantity)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Where did you buy it?") {
                    TextField("Store (e.g., TCGPlayer)", text: $store)
                        .autocorrectionDisabled()
                    if !recentStores.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(recentStores, id: \.self) { recent in
                                    Button(recent) {
                                        store = recent
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section("Order Link (optional)") {
                    TextField("https://...", text: $purchaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: purchaseURL) { _, newValue in
                            // Auto-detect store from URL if store field is empty
                            if store.isEmpty, let detected = PurchaseItem.detectStore(from: newValue) {
                                store = detected
                            }
                        }
                }

                Section("Price Paid (optional)") {
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

                Section("Notes (optional)") {
                    TextField("Tracking number, seller, condition...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Mark as Ordered")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear {
            store = item.store ?? ""
            purchaseURL = item.purchaseURL ?? ""
            pricePaidText = item.pricePaid.map { String(format: "%.2f", $0) } ?? ""
            currency = item.currency ?? "USD"
            notes = item.notes ?? ""
            recentStores = (try? repository.recentStores()) ?? []
        }
    }

    private func save() {
        let price = Double(pricePaidText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ""))
        try? repository.updateItem(
            item,
            status: .ordered,
            store: store,
            purchaseURL: purchaseURL,
            pricePaid: price,
            currency: currency,
            notes: notes
        )
        onDone()
    }
}
