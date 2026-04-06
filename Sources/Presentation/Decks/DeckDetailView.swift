import SwiftUI

/// Shows a deck's purchase checklist grouped by status.
/// Tap items to change status, swipe to delete.
struct DeckDetailView: View {

    let deck: DeckList
    let repository: DeckListRepository

    @State private var items: [PurchaseItem] = []
    @State private var markOrderedItem: PurchaseItem?

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                List {
                    if !needed.isEmpty {
                        Section(header: sectionHeader("Needed", count: needed.count, color: MD3Theme.error)) {
                            ForEach(needed) { item in
                                itemRow(item)
                            }
                            .onDelete(perform: { offsets in delete(offsets, in: needed) })
                        }
                    }
                    if !ordered.isEmpty {
                        Section(header: sectionHeader("Ordered", count: ordered.count, color: .orange)) {
                            ForEach(ordered) { item in
                                itemRow(item)
                            }
                            .onDelete(perform: { offsets in delete(offsets, in: ordered) })
                        }
                    }
                    if !arrived.isEmpty {
                        Section(header: sectionHeader("Arrived", count: arrived.count, color: .green)) {
                            ForEach(arrived) { item in
                                itemRow(item)
                            }
                            .onDelete(perform: { offsets in delete(offsets, in: arrived) })
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $markOrderedItem) { item in
            MarkOrderedSheet(item: item, repository: repository) {
                reload()
                markOrderedItem = nil
            }
        }
        .onAppear { reload() }
    }

    // MARK: - Computed Sections

    private var needed: [PurchaseItem] {
        items.filter { $0.status == .needed }.sorted { $0.cardName < $1.cardName }
    }
    private var ordered: [PurchaseItem] {
        items.filter { $0.status == .ordered }.sorted { ($0.orderedAt ?? .distantPast) > ($1.orderedAt ?? .distantPast) }
    }
    private var arrived: [PurchaseItem] {
        items.filter { $0.status == .arrived }.sorted { ($0.arrivedAt ?? .distantPast) > ($1.arrivedAt ?? .distantPast) }
    }

    private var totalSpent: Double {
        items.compactMap { $0.pricePaid }.reduce(0, +)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("No cards yet")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Add cards from the card detail view by tapping \"Add to Deck\".")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) (\(count))")
                .font(MD3Typography.labelLarge)
        }
    }

    // MARK: - Item Row

    private func itemRow(_ item: PurchaseItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(item.quantity)×")
                    .font(MD3Typography.bodyMedium.monospaced())
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .frame(width: 28, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.cardName)
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                    Text("\(item.setName) #\(item.collectorNumber)")
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                Spacer()
                statusActionButton(item)
            }

            // Purchase metadata (only when ordered/arrived)
            if item.status != .needed {
                metadataRow(item)
                    .padding(.leading, 36)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func metadataRow(_ item: PurchaseItem) -> some View {
        HStack(spacing: 8) {
            if let store = item.store {
                Label(store, systemImage: "bag")
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            if let price = item.pricePaid {
                Text("$\(price, specifier: "%.2f")")
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            if let url = item.purchaseURL, let linkURL = URL(string: url) {
                Link(destination: linkURL) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.primary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Status Action Button

    @ViewBuilder
    private func statusActionButton(_ item: PurchaseItem) -> some View {
        Menu {
            Button {
                markOrderedItem = item
            } label: {
                Label("Mark Ordered", systemImage: "shippingbox")
            }
            .disabled(item.status == .ordered)

            Button {
                try? repository.updateItem(item, status: .arrived)
                reload()
            } label: {
                Label("Mark Arrived", systemImage: "checkmark.circle")
            }
            .disabled(item.status == .arrived)

            if item.status != .needed {
                Button {
                    try? repository.updateItem(item, status: .needed)
                    reload()
                } label: {
                    Label("Reset to Needed", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            Image(systemName: statusIcon(item.status))
                .font(.title3)
                .foregroundStyle(statusColor(item.status))
                .frame(width: 32, height: 32)
        }
    }

    private func statusIcon(_ status: PurchaseStatus) -> String {
        switch status {
        case .needed: return "circle"
        case .ordered: return "shippingbox.fill"
        case .arrived: return "checkmark.circle.fill"
        }
    }

    private func statusColor(_ status: PurchaseStatus) -> Color {
        switch status {
        case .needed: return MD3Theme.onSurfaceVariant
        case .ordered: return .orange
        case .arrived: return .green
        }
    }

    // MARK: - Actions

    private func reload() {
        items = deck.items
    }

    private func delete(_ offsets: IndexSet, in section: [PurchaseItem]) {
        for index in offsets {
            try? repository.deleteItem(section[index])
        }
        reload()
    }
}
