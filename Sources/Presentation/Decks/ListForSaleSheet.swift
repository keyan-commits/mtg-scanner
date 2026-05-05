import SwiftUI

/// Sheet for marking a CollectionItem for sale (or editing an existing
/// listing). Foil and nonfoil are separate sub-quantities with separate
/// asking prices — two listings against one CollectionItem.
///
/// Default asking price = current MTGStocks/Scryfall market price.
/// Channel and notes are free-form for v1; multi-channel pricing is a
/// v2 stretch.
struct ListForSaleSheet: View {
    let item: CollectionItem
    let deckRepository: DeckListRepository
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nonfoilQty: Int = 0
    @State private var foilQty: Int = 0
    @State private var nonfoilPriceUSD: String = ""
    @State private var foilPriceUSD: String = ""
    @State private var listedOn: String = ""
    @State private var notes: String = ""
    @State private var didLoad = false

    private var nonfoilOwned: Int { max(0, item.quantity - item.foilQuantity) }
    private var foilOwned: Int { item.foilQuantity }
    private var hasAnythingToList: Bool { nonfoilOwned > 0 || foilOwned > 0 }

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
                        Text("You own: \(nonfoilOwned) nonfoil, \(foilOwned) foil")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                    .padding(.vertical, 2)
                }

                if foilOwned > 0 {
                    Section("Foil listing") {
                        Stepper(value: $foilQty, in: 0...foilOwned) {
                            HStack {
                                Text("Quantity")
                                Spacer()
                                Text("\(foilQty) of \(foilOwned)")
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                            }
                        }
                        TextField("Asking price (USD per copy)", text: $foilPriceUSD)
                            .keyboardType(.decimalPad)
                    }
                }

                if nonfoilOwned > 0 {
                    Section("Nonfoil listing") {
                        Stepper(value: $nonfoilQty, in: 0...nonfoilOwned) {
                            HStack {
                                Text("Quantity")
                                Spacer()
                                Text("\(nonfoilQty) of \(nonfoilOwned)")
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                            }
                        }
                        TextField("Asking price (USD per copy)", text: $nonfoilPriceUSD)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Listing details") {
                    TextField("Channel (Tambayan, TCGPlayer, Local…)", text: $listedOn)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if item.isListed {
                    Section {
                        Button(role: .destructive) {
                            try? deckRepository.unmarkForSale(item)
                            onClose()
                            dismiss()
                        } label: {
                            Label("Withdraw all listings", systemImage: "tag.slash")
                        }
                    }
                }
            }
            .navigationTitle(item.isListed ? "Edit listing" : "List for sale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasAnythingToList || (nonfoilQty == 0 && foilQty == 0))
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            // Seed from the existing listing if there is one, else default
            // to the current market price so the user just adjusts.
            nonfoilQty = item.forSaleNonfoilQuantity
            foilQty = item.forSaleFoilQuantity
            if let asking = item.askingPriceUSD {
                nonfoilPriceUSD = String(format: "%.2f", asking)
            } else if let market = item.currentValueUSD {
                nonfoilPriceUSD = String(format: "%.2f", market)
            }
            if let asking = item.askingPriceFoilUSD {
                foilPriceUSD = String(format: "%.2f", asking)
            } else if let market = item.currentValueFoilUSD {
                foilPriceUSD = String(format: "%.2f", market)
            }
            listedOn = item.listedOn ?? ""
            notes = item.saleNotes ?? ""
        }
    }

    private func save() {
        try? deckRepository.markForSale(
            item,
            nonfoilQuantity: nonfoilQty,
            foilQuantity: foilQty,
            askingPriceUSD: Double(nonfoilPriceUSD.trimmingCharacters(in: .whitespaces)),
            askingPriceFoilUSD: Double(foilPriceUSD.trimmingCharacters(in: .whitespaces)),
            listedOn: listedOn.trimmingCharacters(in: .whitespaces).isEmpty ? nil : listedOn,
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        )
        onClose()
        dismiss()
    }
}
