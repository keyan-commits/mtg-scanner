import SwiftUI

/// Top-level list of every bulk Order across every deck, newest first.
/// Tap an order to drill into its items and mark them arrived.
struct OrdersScreen: View {

    let repository: DeckListRepository
    /// When set, only shows orders that contain at least one item from this deck.
    var deckID: UUID? = nil
    var titleOverride: String? = nil

    @State private var orders: [Order] = []
    @State private var pendingDelete: Order?

    var body: some View {
        Group {
            if orders.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(orders) { order in
                        NavigationLink {
                            OrderDetailView(order: order, repository: repository, onChanged: reload)
                        } label: {
                            orderRow(order)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = order
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(titleOverride ?? "Orders")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ScreenHelpButton(title: "Orders", sections: [
                    HelpSection(icon: "shippingbox", title: "What lives here",
                                body: "Every bulk order you've placed shows up here, newest first. The Shopping List shows what you still need; this screen shows what you've already bought."),
                    HelpSection(icon: "checkmark.seal.fill", title: "Status badges",
                                body: "Green seal = every card in the order has arrived. Orange clock + ETA = still in transit. The X/Y arrived count below the store name tracks delivery progress."),
                    HelpSection(icon: "trash", title: "Delete an order",
                                body: "Swipe left to delete. The cards inside the order are reset to Needed in their decks — they're not removed entirely. Useful when re-doing a paste with corrections."),
                    HelpSection(icon: "hand.tap", title: "Tap to drill in",
                                body: "Tap a row to see the order's full info, mark all items arrived, edit the order header, or fix a typo on individual card prices."),
                ])
            }
        }
        .onAppear { reload() }
        .alert("Delete this order?", isPresented: .init(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let target = pendingDelete {
                    try? repository.deleteOrder(target)
                    pendingDelete = nil
                    reload()
                }
            }
        } message: {
            if let target = pendingDelete {
                Text("\(target.items.count) item(s) in this order will be reset to Needed in their decks. The cards themselves are not deleted.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("No orders yet")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Open the Shopping List or a deck to mark cards as ordered. Orders show up here once placed.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Row

    private func orderRow(_ order: Order) -> some View {
        let totalCards = order.items.count
        let arrivedCount = order.items.filter { $0.status == .arrived }.count
        let allArrived = arrivedCount == totalCards && totalCards > 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(order.store)
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
                if allArrived {
                    Label("Arrived", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if let eta = order.eta {
                    Label(formatShortDate(eta), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 10) {
                Text(formatShortDate(order.orderedAt))
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Text("·")
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Text("\(arrivedCount)/\(totalCards) arrived")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Spacer()
                if let total = order.totalDue {
                    Text("\(order.currency) \(formatPrice(total))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MD3Theme.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func reload() {
        orders = (try? repository.fetchOrders(deckID: deckID)) ?? []
    }

    private func formatShortDate(_ date: Date) -> String { ShortDate.format(date) }
    private func formatPrice(_ price: Double) -> String { MoneyFormat.compact(price) }
}
