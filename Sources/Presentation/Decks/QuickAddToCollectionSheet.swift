import SwiftUI

/// Compact "Add to Collection" sheet for a card that's already been
/// identified. Shows a preview + quantity/foil pickers + one-tap add.
///
/// Used from:
/// - `ScannedCardsListView` (each row's quick-add button)
/// - `CardDetailView` ("Add to Collection" button)
///
/// For the search-first flow (user types a name), use the existing
/// `AddToCollectionSheet` instead.
struct QuickAddToCollectionSheet: View {

    let card: Card
    let deckRepository: DeckListRepository
    let onAdded: () -> Void

    @State private var quantity: Int = 1
    @State private var foilQuantity: Int = 0
    @State private var didAdd: Bool = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Card preview
                HStack(spacing: 12) {
                    if let urlString = card.imageURIs["small"]
                        ?? card.imageURIs["normal"],
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            default:
                                thumbPlaceholder
                            }
                        }
                        .frame(width: 60)
                    } else {
                        thumbPlaceholder
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                        Text("\(card.setNameWithYear) · #\(card.collectorNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let usd = card.prices.usd {
                            Text("$\(usd)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(MD3Theme.primary)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 8)

                // Quantity controls
                VStack(spacing: 12) {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                    Stepper("Foil: \(foilQuantity)", value: $foilQuantity, in: 0...quantity)
                }
                .padding(.horizontal, 4)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                // Add button
                Button {
                    addToCollection()
                } label: {
                    Label(
                        didAdd ? "Added!" : "Add to Collection",
                        systemImage: didAdd ? "checkmark.circle.fill" : "plus.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .background(didAdd ? .green : MD3Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(didAdd)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var thumbPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(MD3Theme.surfaceVariant)
            .frame(width: 60, height: 84)
    }

    private func addToCollection() {
        do {
            _ = try deckRepository.addToCollection(
                card: card,
                quantity: quantity,
                foilQuantity: foilQuantity
            )
            didAdd = true
            // Haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            // Auto-dismiss after brief confirmation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                onAdded()
                dismiss()
            }
        } catch {
            self.error = "Failed to add: \(error.localizedDescription)"
        }
    }
}
