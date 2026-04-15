import SwiftUI

/// Combines the Shopping List and Orders screens under one tab with a
/// segmented picker. Pre-purchase (wishlist) on one side, post-purchase
/// (order tracking) on the other — same lifecycle, two ends of it.
struct ShopView: View {

    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol

    @State private var section: Section = .shopping

    enum Section: String, CaseIterable, Identifiable {
        case shopping = "Shopping List"
        case orders = "Orders"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            switch section {
            case .shopping:
                ShoppingListScreen(deckRepository: deckRepository, cardRepository: cardRepository)
            case .orders:
                OrdersScreen(repository: deckRepository)
            }
        }
        .background(MD3Theme.background)
    }
}
