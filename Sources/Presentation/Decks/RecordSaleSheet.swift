import SwiftUI

/// Sheet for marking listed copies as sold. Decrements both the
/// CollectionItem's owned quantity AND the for-sale subset; increments
/// the historical sold counter and stamps lastSoldAt + lastSoldPriceUSD.
///
/// The "P&L vs purchase price" callout only renders when the user has a
/// `purchasePrice` recorded — derives margin per copy on the fly.
struct RecordSaleSheet: View {
    let item: CollectionItem
    let deckRepository: DeckListRepository
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isFoil: Bool = false
    @State private var soldQty: Int = 1
    @State private var soldPriceUSD: String = ""
    @State private var didLoad = false

    private var maxFoil: Int { item.forSaleFoilQuantity }
    private var maxNonfoil: Int { item.forSaleNonfoilQuantity }
    private var canSellFoil: Bool { maxFoil > 0 }
    private var canSellNonfoil: Bool { maxNonfoil > 0 }
    private var maxAvailable: Int { isFoil ? maxFoil : maxNonfoil }

    private var marginPerCopy: Double? {
        guard let price = Double(soldPriceUSD), price > 0,
              let paid = item.purchasePrice, paid > 0 else { return nil }
        return price - paid
    }

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

                if canSellFoil && canSellNonfoil {
                    Section("Finish sold") {
                        Picker("Finish", selection: $isFoil) {
                            Text("Nonfoil (\(maxNonfoil) listed)").tag(false)
                            Text("Foil (\(maxFoil) listed)").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Quantity sold") {
                    Stepper(value: $soldQty, in: 1...max(maxAvailable, 1)) {
                        HStack {
                            Text("Quantity")
                            Spacer()
                            Text("\(soldQty) of \(maxAvailable) listed")
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                    }
                }

                Section("Sold price") {
                    TextField("Per-copy price (USD)", text: $soldPriceUSD)
                        .keyboardType(.decimalPad)
                    if let margin = marginPerCopy {
                        let total = margin * Double(soldQty)
                        let label = total >= 0
                            ? String(format: "+ $%.2f profit (vs paid $%.2f/copy)", total, item.purchasePrice ?? 0)
                            : String(format: "- $%.2f loss (vs paid $%.2f/copy)", abs(total), item.purchasePrice ?? 0)
                        Text(label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(total >= 0 ? .green : .red)
                    }
                }
            }
            .navigationTitle("Record sale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark sold") { recordSale() }
                        .disabled(maxAvailable == 0)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            // Default to foil if foil is the only thing listed; otherwise
            // nonfoil. Keeps the common case 1-tap.
            isFoil = canSellFoil && !canSellNonfoil
            soldQty = max(1, min(soldQty, maxAvailable))
            // Default sold price to the asking price.
            let asking = isFoil ? item.askingPriceFoilUSD : item.askingPriceUSD
            if let asking {
                soldPriceUSD = String(format: "%.2f", asking)
            }
        }
        .onChange(of: isFoil) { (_: Bool, newValue: Bool) in
            soldQty = max(1, min(soldQty, maxAvailable))
            let asking = newValue ? item.askingPriceFoilUSD : item.askingPriceUSD
            if let asking { soldPriceUSD = String(format: "%.2f", asking) }
        }
    }

    private func recordSale() {
        try? deckRepository.recordSale(
            item,
            isFoil: isFoil,
            quantity: soldQty,
            soldPriceUSD: Double(soldPriceUSD.trimmingCharacters(in: .whitespaces))
        )
        onClose()
        dismiss()
    }
}
