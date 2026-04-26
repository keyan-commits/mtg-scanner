import SwiftUI

/// Detail screen pushed from DeckDetailView when tapping a card row.
/// Shows all copies of one card and lets the user manage each copy individually
/// (mark needed/ordered/arrived) plus bulk actions.
struct CardCopiesDetailView: View {

    let cardName: String
    let initialSetCode: String
    let initialCollectorNumber: String
    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol?
    let deckID: UUID

    /// Current printing identity. Mutates when the user changes printing
    /// so the per-copy list and card info follow the new selection.
    @State private var setCode: String
    @State private var collectorNumber: String
    @State private var copies: [PurchaseItem] = []
    @State private var card: Card?
    @State private var markOrderedItem: PurchaseItem?
    @State private var showChangePrinting: Bool = false
    @State private var showFullImage: Bool = false
    @State private var phListings: [TCGPHListing] = []
    @State private var phLoading: Bool = false
    @Environment(\.dismiss) private var dismiss

    init(
        cardName: String,
        setCode: String,
        collectorNumber: String,
        deckRepository: DeckListRepository,
        cardRepository: CardRepositoryProtocol?,
        deckID: UUID
    ) {
        self.cardName = cardName
        self.initialSetCode = setCode
        self.initialCollectorNumber = collectorNumber
        self.deckRepository = deckRepository
        self.cardRepository = cardRepository
        self.deckID = deckID
        self._setCode = State(initialValue: setCode)
        self._collectorNumber = State(initialValue: collectorNumber)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Card image + header
                if let card {
                    cardHeader(card)
                } else {
                    placeholderHeader
                }

                // Change printing button
                changePrintingButton
                    .padding(.horizontal, 16)

                // Type line + oracle text
                if let card {
                    cardInfoSection(card)
                        .padding(.horizontal, 16)
                    PriceComparisonView(card: card)
                        .padding(.horizontal, 16)
                    if let cardRepository {
                        CardInsightView(card: card, cardRepository: cardRepository)
                            .padding(.horizontal, 16)
                    }
                    phStoresSection(card)
                        .padding(.horizontal, 16)
                    legalitySection(card)
                        .padding(.horizontal, 16)
                }

                Divider().padding(.vertical, 4)

                // Related orders
                if !relatedOrders.isEmpty {
                    relatedOrdersSection
                        .padding(.horizontal, 16)
                }

                // Summary stats
                summaryStats
                    .padding(.horizontal, 16)

                // Bulk actions
                bulkActionsRow
                    .padding(.horizontal, 16)

                // Per-copy list
                copiesList
                    .padding(.horizontal, 16)

                Spacer(minLength: 32)
            }
            .padding(.top, 12)
        }
        .background(MD3Theme.background)
        .navigationTitle(cardName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $markOrderedItem) { item in
            MarkOrderedSheet(item: item, repository: deckRepository) {
                markOrderedItem = nil
                reload()
            }
        }
        .sheet(isPresented: $showChangePrinting) {
            if let cardRepository, let first = copies.first {
                ChangePrintingSheet(
                    item: first,
                    deckRepository: deckRepository,
                    cardRepository: cardRepository,
                    onChanged: {
                        Task { await reloadAfterPrintingChange() }
                    },
                    applyToAll: copies
                )
            }
        }
        .task {
            reload()
            await loadCard()
            await loadPHListings()
        }
    }

    // MARK: - PH Stores

    @ViewBuilder
    private func phStoresSection(_ card: Card) -> some View {
        if phLoading {
            MD3Card {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Checking PH stores\u{2026}")
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            MD3Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("PH Stores")
                            .font(MD3Typography.titleMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                        Spacer()
                        if !phListings.isEmpty {
                            Text("\(phListings.count) listing\(phListings.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                    }

                    if phListings.isEmpty {
                        Text("No listings found")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    } else {
                        ForEach(phListings) { listing in
                            HStack(spacing: 8) {
                                Text(listing.storeName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(MD3Theme.onSurface)
                                    .lineLimit(1)
                                Spacer()
                                Text("₱\(String(format: "%.0f", listing.price))")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(MD3Theme.primary)
                            }
                        }
                    }

                    // Links
                    HStack(spacing: 16) {
                        let slug = card.name.lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                            .replacingOccurrences(of: ",", with: "")
                            .replacingOccurrences(of: "'", with: "")
                        if let url = URL(string: "https://tcgph.com/card/\(slug)") {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "magnifyingglass").font(.caption)
                                    Text("tcgph.com")
                                }
                                .font(MD3Typography.labelLarge)
                                .foregroundStyle(MD3Theme.primary)
                            }
                        }
                        Spacer()
                        let query = card.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "https://www.facebook.com/groups/135914699791891/search/?q=\(query)") {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.3.fill").font(.caption)
                                    Text("MTG Tambayan")
                                }
                                .font(MD3Typography.labelLarge)
                                .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func loadPHListings() async {
        guard let card else { return }
        phLoading = true
        let result = await TCGPHService.shared.fetchListings(
            setCode: card.set.code,
            collectorNumber: card.collectorNumber,
            cardName: card.name
        )
        phListings = result?.listings ?? []
        phLoading = false
    }

    // MARK: - Change Printing

    @ViewBuilder
    private var changePrintingButton: some View {
        if cardRepository != nil {
            Button {
                showChangePrinting = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.stack")
                    Text("Change Printing")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MD3Theme.primary)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(MD3Theme.primaryContainer.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    /// After ChangePrintingSheet applies a new card, the printing fields on
    /// every copy have been rewritten. Refetch a copy to discover the new
    /// set/collector and re-load both the card info and the filtered copies list.
    private func reloadAfterPrintingChange() async {
        let all = (try? deckRepository.fetchItems(deckID: deckID)) ?? []
        // Find any copy that still belongs to this card name — its set/collector
        // is now the freshly chosen printing.
        if let updated = all.first(where: { $0.cardName == cardName }) {
            setCode = updated.setCode
            collectorNumber = updated.collectorNumber
        }
        copies = all
            .filter { $0.cardName == cardName && $0.setCode == setCode && $0.collectorNumber == collectorNumber }
            .sorted { $0.addedAt < $1.addedAt }
        card = nil
        await loadCard()
    }

    // MARK: - Card Info Sections

    @ViewBuilder
    private func cardInfoSection(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !card.typeLine.isEmpty {
                Text(card.typeLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurface)
            }
            if let oracleText = card.oracleText, !oracleText.isEmpty {
                Text(oracleText)
                    .font(.callout)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(rarityLabel(card.rarity))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rarityColor(card.rarity))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(rarityColor(card.rarity).opacity(0.15))
                    .clipShape(Capsule())
                if let artist = card.artist, !artist.isEmpty {
                    Text("Illus. \(artist)")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MD3Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MD3Theme.outlineVariant, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func legalitySection(_ card: Card) -> some View {
        let formats: [(String, String)] = [
            ("Standard", "standard"),
            ("Pioneer", "pioneer"),
            ("Modern", "modern"),
            ("Legacy", "legacy"),
            ("Vintage", "vintage"),
            ("Pauper", "pauper"),
            ("Commander", "commander"),
            ("Premodern", "premodern"),
        ]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Format Legality")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurface)
                HelpButton("Whether this card is allowed in each tournament format. Restricted = limited to 1 copy in the deck.")
            }
            ForEach(formats, id: \.1) { name, key in
                let status = card.legalities.status(for: key) ?? .notLegal
                HStack {
                    Circle()
                        .fill(legalityColor(status))
                        .frame(width: 8, height: 8)
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurface)
                    Spacer()
                    Text(legalityLabel(status))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(legalityColor(status))
                }
            }
        }
        .padding(14)
        .background(MD3Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MD3Theme.outlineVariant, lineWidth: 1)
        )
    }

    private func rarityLabel(_ rarity: CardRarity) -> String {
        switch rarity {
        case .mythic: return "Mythic"
        case .rare: return "Rare"
        case .uncommon: return "Uncommon"
        case .common: return "Common"
        }
    }

    private func rarityColor(_ rarity: CardRarity) -> Color {
        switch rarity {
        case .mythic: return .orange
        case .rare: return .yellow
        case .uncommon: return .gray
        case .common: return Color(white: 0.5)
        }
    }

    private func legalityColor(_ status: LegalityStatus) -> Color {
        switch status {
        case .legal: return .green
        case .banned: return .red
        case .restricted: return .orange
        case .notLegal: return .gray
        }
    }

    private func legalityLabel(_ status: LegalityStatus) -> String {
        switch status {
        case .legal: return "Legal"
        case .banned: return "Banned"
        case .restricted: return "Restricted"
        case .notLegal: return "Not legal"
        }
    }

    // MARK: - Related Orders

    /// Distinct orders that any of these copies belong to, newest first.
    private var relatedOrders: [Order] {
        var seen: Set<UUID> = []
        var result: [Order] = []
        for copy in copies {
            if let order = copy.order, !seen.contains(order.id) {
                seen.insert(order.id)
                result.append(order)
            }
        }
        return result.sorted { $0.orderedAt > $1.orderedAt }
    }

    @ViewBuilder
    private var relatedOrdersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related Orders")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurface)
            VStack(spacing: 0) {
                ForEach(Array(relatedOrders.enumerated()), id: \.element.id) { idx, order in
                    NavigationLink {
                        OrderDetailView(order: order, repository: deckRepository, onChanged: { reload() })
                    } label: {
                        relatedOrderRow(order)
                    }
                    .buttonStyle(.plain)
                    if idx < relatedOrders.count - 1 {
                        Divider()
                    }
                }
            }
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func relatedOrderRow(_ order: Order) -> some View {
        let copiesInOrder = copies.filter { $0.order?.id == order.id }
        let arrived = copiesInOrder.filter { $0.status == .arrived }.count
        HStack(spacing: 10) {
            Image(systemName: arrived == copiesInOrder.count ? "checkmark.seal.fill" : "shippingbox.fill")
                .foregroundStyle(arrived == copiesInOrder.count ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(order.store)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(MD3Theme.onSurface)
                    Spacer()
                    Text("\(copiesInOrder.count) cop\(copiesInOrder.count == 1 ? "y" : "ies")")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                HStack(spacing: 6) {
                    Text(formatOrderDate(order.orderedAt))
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                    if let eta = order.eta {
                        Text("· ETA \(formatOrderDate(eta))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if let representative = copiesInOrder.first, let price = representative.pricePaid {
                        Text("\(representative.currency ?? order.currency) \(formatOrderPrice(price)) ea")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private func formatOrderDate(_ date: Date) -> String { ShortDate.format(date) }
    private func formatOrderPrice(_ price: Double) -> String { MoneyFormat.compact(price) }

    // MARK: - Header

    @ViewBuilder
    private func cardHeader(_ card: Card) -> some View {
        VStack(spacing: 8) {
            if let urlString = card.imageURIs["normal"] ?? card.imageURIs["large"],
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { showFullImage = true }
                    default:
                        placeholderImage
                    }
                }
                .frame(maxWidth: 280, maxHeight: 380)
                .fullScreenCover(isPresented: $showFullImage) {
                    ZStack(alignment: .topTrailing) {
                        Color.black.ignoresSafeArea()
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit).ignoresSafeArea()
                            default:
                                ProgressView().tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Button { showFullImage = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(20)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text(card.name)
                    .font(.headline)
                if let manaCost = card.manaCost, !manaCost.isEmpty {
                    ManaCostView(cost: manaCost, size: 16)
                    HelpButton("Mana cost to cast this spell. W=White, U=Blue, B=Black, R=Red, G=Green, C=Colorless. Numbers are generic mana of any color.")
                }
            }
            HStack(spacing: 4) {
                Text("\(card.setNameWithYear) #\(card.collectorNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HelpButton("Set name + collector number identifies which printing of the card this is. The same card may be reprinted in different sets at different prices.", size: 11)
            }
        }
    }

    private var placeholderHeader: some View {
        VStack(spacing: 8) {
            placeholderImage
            Text(cardName).font(.headline)
            Text("\(setCode.uppercased()) #\(collectorNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.15))
            .frame(width: 200, height: 280)
    }

    // MARK: - Summary

    private var summaryStats: some View {
        let needed = copies.filter { $0.status == .needed }.count
        let ordered = copies.filter { $0.status == .ordered }.count
        let arrived = copies.filter { $0.status == .arrived }.count
        return HStack(spacing: 16) {
            statTile(label: "Total", value: copies.count, color: MD3Theme.onSurface)
            statTile(label: "Needed", value: needed, color: MD3Theme.error)
            statTile(label: "Ordered", value: ordered, color: .orange)
            statTile(label: "Arrived", value: arrived, color: .green)
            Spacer()
        }
    }

    private func statTile(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    // MARK: - Bulk Actions

    private var bulkActionsRow: some View {
        HStack(spacing: 8) {
            Button {
                for copy in copies where copy.status == .needed {
                    markOrderedItem = copy
                    return // sheet handles single item; user can repeat
                }
            } label: {
                Label("Mark First Needed as Ordered", systemImage: "shippingbox")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            Spacer()
            Menu {
                Button {
                    markAll(.arrived)
                } label: {
                    Label("Mark All Arrived", systemImage: "checkmark.circle")
                }
                Button {
                    markAll(.needed)
                } label: {
                    Label("Reset All to Needed", systemImage: "arrow.uturn.backward")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
    }

    // MARK: - Per-copy List

    private var copiesList: some View {
        VStack(spacing: 0) {
            ForEach(Array(copies.enumerated()), id: \.element.id) { index, copy in
                copyRow(index: index + 1, copy: copy)
                if index < copies.count - 1 {
                    Divider()
                }
            }
        }
        .background(MD3Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MD3Theme.outlineVariant, lineWidth: 1)
        )
    }

    private func copyRow(index: Int, copy: PurchaseItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Copy \(index)")
                    .font(.body)
                    .foregroundStyle(MD3Theme.onSurface)
                if let price = copy.pricePaid {
                    Text("\(copy.currency ?? "USD") \(MoneyFormat.compact(price))")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
            Spacer()
            if let store = copy.store, !store.isEmpty {
                Text(store)
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            statusMenu(for: copy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func statusMenu(for item: PurchaseItem) -> some View {
        Menu {
            Button {
                try? deckRepository.updateItem(item, status: .needed)
                reload()
            } label: {
                Label("Needed", systemImage: "circle")
            }
            .disabled(item.status == .needed)

            Button {
                markOrderedItem = item
            } label: {
                Label("Mark Ordered", systemImage: "shippingbox")
            }
            .disabled(item.status == .ordered)

            Button {
                try? deckRepository.updateItem(item, status: .arrived)
                reload()
            } label: {
                Label("Mark Arrived", systemImage: "checkmark.circle")
            }
            .disabled(item.status == .arrived)

            Divider()

            Button(role: .destructive) {
                try? deckRepository.deleteItem(item)
                reload()
            } label: {
                Label("Delete Copy", systemImage: "trash")
            }
        } label: {
            statusBadge(item.status)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PurchaseStatus) -> some View {
        switch status {
        case .needed:
            Text("Needed")
                .font(.caption.weight(.medium))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(
                    Capsule().stroke(MD3Theme.outline, lineWidth: 1)
                )
        case .ordered:
            HStack(spacing: 4) {
                Image(systemName: "shippingbox.fill")
                Text("Ordered")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange)
            .clipShape(Capsule())
        case .arrived:
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                Text("Arrived")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.green)
            .clipShape(Capsule())
        }
    }

    // MARK: - Data

    private func reload() {
        let all = (try? deckRepository.fetchItems(deckID: deckID)) ?? []
        copies = all
            .filter { $0.cardName == cardName && $0.setCode == setCode && $0.collectorNumber == collectorNumber }
            .sorted { $0.addedAt < $1.addedAt }
    }

    private func loadCard() async {
        guard let cardRepository, card == nil else { return }
        card = try? await cardRepository.fetchCard(set: setCode, collectorNumber: collectorNumber)
    }

    private func markAll(_ status: PurchaseStatus) {
        for copy in copies {
            try? deckRepository.updateItem(copy, status: status)
        }
        reload()
    }
}
