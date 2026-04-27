import SwiftUI

/// Drill-down view for a single bulk Order. Shows the items, deck attribution,
/// and bulk actions to mark all arrived or delete the order.
struct OrderDetailView: View {

    let order: Order
    let repository: DeckListRepository
    let onChanged: () -> Void

    @State private var showDeleteConfirm: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var editingItems: ItemGroupSelection?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Wrapper so we can use `.sheet(item:)` with an array of PurchaseItems.
    struct ItemGroupSelection: Identifiable {
        let id = UUID()
        let items: [PurchaseItem]
    }

    var body: some View {
        List {
            Section("Order Info") {
                infoRow(label: "Store", value: order.store)
                infoRow(label: "Ordered", value: formatDate(order.orderedAt))
                if let eta = order.eta {
                    infoRow(label: "ETA", value: formatDate(eta))
                }
                infoRow(label: "Currency", value: order.currency)
                if let total = order.totalDue {
                    infoRow(label: "Total Due", value: "\(order.currency) \(formatPrice(total))")
                }
                if let url = order.purchaseURL, !url.isEmpty, let parsed = URL(string: url) {
                    Button {
                        openURL(parsed)
                    } label: {
                        HStack {
                            Text("Order Link")
                                .foregroundStyle(MD3Theme.onSurface)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(MD3Theme.primary)
                        }
                    }
                }
                if let notes = order.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }

            Section {
                ForEach(itemsByCard, id: \.key) { entry in
                    itemGroupRow(name: entry.key, items: entry.value)
                }
            } header: {
                HStack {
                    Text("Items")
                    Spacer()
                    Text("\(order.items.count) copies")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Tap a row to fix the price, store, currency, or notes for those copies.")
                    .font(.caption2)
            }

            Section {
                Button {
                    markAllArrived()
                } label: {
                    Label("Mark All Arrived", systemImage: "checkmark.circle.fill")
                }
                .disabled(allArrived)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Order (reset items to Needed)", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(order.store)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    ScreenHelpButton(title: "Order Detail", sections: [
                        HelpSection(icon: "pencil", title: "Edit the header",
                                    body: "The pencil button opens a sheet for the order's store, currency, ETA, total due, URL, and notes. Saving cascades store/currency/URL/date to every linked card."),
                        HelpSection(icon: "hand.tap", title: "Edit individual cards",
                                    body: "Tap any card row in the Items section to fix a typo on the per-card price, store, currency, or notes. Edits apply to all copies of that card in the order at once."),
                        HelpSection(icon: "checkmark.circle.fill", title: "Mark all arrived",
                                    body: "When the package shows up, hit Mark All Arrived. Every linked card flips to Arrived in its deck and the order shows the green seal."),
                        HelpSection(icon: "trash", title: "Delete vs reset",
                                    body: "Delete Order removes the order grouping and resets every linked card back to Needed in its deck — but the cards themselves stay. Use this when you need to redo a paste."),
                    ])
                    Button {
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditOrderSheet(order: order, repository: repository) {
                showEditSheet = false
                onChanged()
            }
        }
        .sheet(item: $editingItems) { selection in
            EditOrderItemSheet(items: selection.items, repository: repository) {
                editingItems = nil
                onChanged()
            }
        }
        .alert("Delete this order?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteOrder() }
        } message: {
            Text("The \(order.items.count) item(s) in this order will be reset to Needed in their decks. The cards themselves are not deleted.")
        }
    }

    // MARK: - Items

    private var itemsByCard: [(key: String, value: [PurchaseItem])] {
        let grouped = Dictionary(grouping: order.items) { "\($0.cardName)|\($0.setCode)" }
        return grouped
            .map { (key: $0.value.first?.cardName ?? "", value: $0.value) }
            .sorted { $0.key < $1.key }
    }

    private var allArrived: Bool {
        !order.items.isEmpty && order.items.allSatisfy { $0.status.isCollected }
    }

    @ViewBuilder
    private func itemGroupRow(name: String, items: [PurchaseItem]) -> some View {
        let arrived = items.filter { $0.status.isCollected }.count
        let total = items.count
        let representative = items[0]
        let deckName = representative.deck?.name ?? "—"
        Button {
            editingItems = ItemGroupSelection(items: items)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(total)× \(name)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MD3Theme.onSurface)
                    Spacer()
                    if arrived == total {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("\(arrived)/\(total)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.primary)
                }
                HStack {
                    Text("\(representative.setName) #\(representative.collectorNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Deck: \(deckName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let price = representative.pricePaid {
                    Text("\(representative.currency ?? order.currency) \(formatPrice(price)) ea")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func markAllArrived() {
        try? repository.markOrderArrived(order)
        onChanged()
        dismiss()
    }

    private func deleteOrder() {
        try? repository.deleteOrder(order)
        onChanged()
        dismiss()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Spacer()
            Text(value)
                .foregroundStyle(MD3Theme.onSurface)
        }
    }

    private func formatDate(_ date: Date) -> String { ShortDate.format(date) }
    private func formatPrice(_ price: Double) -> String { MoneyFormat.compact(price) }
}
