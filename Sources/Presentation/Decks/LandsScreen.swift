import SwiftUI

/// Browse curated card lists — Lands and cEDH Staples. Each category
/// opens a detail view with list/visual toggle, where every card is
/// tappable and shows owned quantity from the user's collection.
struct LandsScreen: View {

    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    var body: some View {
        List {
            Section("Price Lists") {
                NavigationLink {
                    TopBasicLandsScreen(
                        cardRepository: cardRepository,
                        deckRepository: deckRepository
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Top 100 Basic Lands")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(MD3Theme.onSurface)
                            Text("Most expensive basic lands by price")
                                .font(.caption2)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Lands") {
                ForEach(LandLists.all) { category in
                    categoryRow(category)
                }
            }
            Section("Collectible Lands") {
                ForEach(CollectibleLands.all) { category in
                    categoryRow(category)
                }
            }
            Section("cEDH Staples") {
                ForEach(CEDHStaples.all) { category in
                    categoryRow(category)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryRow(_ category: LandCategory) -> some View {
        NavigationLink {
            LandCategoryDetailView(
                category: category,
                cardRepository: cardRepository,
                deckRepository: deckRepository
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MD3Theme.primary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                    Text("\(category.cardNames.count) cards")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Category Detail View

/// Shows all cards in a land category with list/visual toggle.
/// Each card is resolved via `CardResolver` (honoring the user's
/// Default Printing setting) and tappable → `CardDetailView`.
struct LandCategoryDetailView: View {

    let category: LandCategory
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var viewMode: ViewMode = .list
    @State private var resolvedCards: [String: Card] = [:]
    @State private var sortByPrice: Bool = false
    /// Owned quantities from the user's collection, keyed by card name (any printing).
    @State private var ownedByName: [String: Int] = [:]
    /// Per-printing ownership data: [cardName: [(setCode, quantity)]].
    /// Used when the category has setCodes to distinguish exact vs different-expansion ownership.
    @State private var ownedDetails: [String: [(setCode: String, quantity: Int)]] = [:]

    private enum ViewMode: String, CaseIterable, Hashable {
        case list, grid
        var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    /// Card names sorted based on current sort mode. Default is the
    /// curated order from `LandLists`; when sort-by-price is on, cards
    /// with resolved prices are sorted descending (most expensive first),
    /// followed by unresolved cards in their original order.
    private var sortedCardNames: [String] {
        guard sortByPrice else { return category.cardNames }
        return category.cardNames.sorted { a, b in
            let pa = resolvedCards[a].flatMap { Double($0.prices.usd ?? "") } ?? -1
            let pb = resolvedCards[b].flatMap { Double($0.prices.usd ?? "") } ?? -1
            return pa > pb
        }
    }

    var body: some View {
        Group {
            switch viewMode {
            case .list:
                listBody
            case .grid:
                gridBody
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    sortByPrice.toggle()
                } label: {
                    Image(systemName: sortByPrice ? "dollarsign.circle.fill" : "dollarsign.circle")
                        .foregroundStyle(sortByPrice ? MD3Theme.primary : MD3Theme.onSurfaceVariant)
                }
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
        }
        .onAppear {
            ownedByName = (try? deckRepository.ownedQuantitiesByName()) ?? [:]
            if !category.setCodes.isEmpty {
                ownedDetails = (try? deckRepository.ownedDetailsByName()) ?? [:]
            }
        }
    }

    // MARK: - List

    private var listBody: some View {
        List {
            Section {
                Text(category.description)
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .listRowBackground(Color.clear)
            }
            Section("\(category.cardNames.count) cards") {
                ForEach(sortedCardNames, id: \.self) { name in
                    if let card = resolvedCards[name] {
                        NavigationLink {
                            CardDetailView(
                                card: card,
                                repository: cardRepository,
                                deckRepository: deckRepository,
                                onScanAnother: {}
                            )
                        } label: {
                            listRow(name: name, card: card)
                        }
                    } else {
                        listRow(name: name, card: nil)
                            .task { await resolve(name: name) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Ownership status for a card in a set-aware category.
    private enum OwnershipStatus {
        case exactMatch(Int)       // Owns this exact printing
        case differentSet(Int)     // Owns the card but in a different set
        case notOwned
    }

    /// Determines ownership status for a card name, considering set codes if available.
    private func ownershipStatus(for name: String) -> OwnershipStatus {
        if category.setCodes.isEmpty {
            // No set filtering — any printing counts (legacy behavior)
            let owned = ownedByName[name] ?? 0
            return owned > 0 ? .exactMatch(owned) : .notOwned
        }
        // Set-aware: check if user owns a printing from the category's set codes
        let details = ownedDetails[name] ?? []
        let exactQty = details
            .filter { category.setCodes.contains($0.setCode) }
            .reduce(0) { $0 + $1.quantity }
        if exactQty > 0 { return .exactMatch(exactQty) }
        let anyQty = ownedByName[name] ?? 0
        if anyQty > 0 { return .differentSet(anyQty) }
        return .notOwned
    }

    private func listRow(name: String, card: Card?) -> some View {
        let status = ownershipStatus(for: name)
        return HStack(spacing: 12) {
            // Owned quantity badge
            switch status {
            case .exactMatch(let qty):
                Text("\(qty)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.green)
                    .clipShape(Circle())
            case .differentSet(let qty):
                Text("\(qty)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.orange)
                    .clipShape(Circle())
            case .notOwned:
                Circle()
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text("0")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)
                    if let manaCost = card?.manaCost, !manaCost.isEmpty {
                        ManaCostView(cost: manaCost, size: 12)
                    }
                }
                HStack(spacing: 4) {
                    if let card {
                        Text(card.setNameWithYear)
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                    if case .differentSet = status {
                        Text("(owned in different set)")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer(minLength: 8)
            if let usd = card?.prices.usd {
                Text("$\(usd)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.primary)
                    .monospacedDigit()
            }
            if card != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
            } else {
                ProgressView().scaleEffect(0.5)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Grid

    private var gridBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(category.description)
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(sortedCardNames, id: \.self) { name in
                        gridCard(name: name)
                    }
                }
                .padding(.horizontal, 16)

                Color.clear.frame(height: 24)
            }
        }
        .background(MD3Theme.background)
    }

    @ViewBuilder
    private func gridCard(name: String) -> some View {
        let card = resolvedCards[name]
        Group {
            if let card {
                NavigationLink {
                    CardDetailView(
                        card: card,
                        repository: cardRepository,
                        deckRepository: deckRepository,
                        onScanAnother: {}
                    )
                } label: {
                    gridCardLabel(name: name, card: card)
                }
                .buttonStyle(.plain)
            } else {
                gridCardLabel(name: name, card: nil)
                    .task { await resolve(name: name) }
            }
        }
    }

    private func gridCardLabel(name: String, card: Card?) -> some View {
        let status = ownershipStatus(for: name)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let card,
                   let urlString = card.imageURIs["normal"]
                       ?? card.imageURIs["small"]
                       ?? card.imageURIs["large"],
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(63.0 / 88.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        default:
                            gridPlaceholder(name)
                        }
                    }
                } else {
                    gridPlaceholder(name)
                }
                // Owned badge
                switch status {
                case .exactMatch(let qty):
                    Text("\(qty)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.green)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                case .differentSet(let qty):
                    Text("\(qty)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.orange)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                case .notOwned:
                    EmptyView()
                }
            }
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MD3Theme.onSurface)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private func gridPlaceholder(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(MD3Theme.surfaceVariant)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .overlay(
                Text(name)
                    .font(.system(size: 8))
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    // MARK: - Resolution

    private func resolve(name: String) async {
        guard resolvedCards[name] == nil else { return }

        // When the category specifies set codes, find a printing from those sets
        if !category.setCodes.isEmpty {
            if let printings = try? await cardRepository.findAllPrintings(name: name) {
                let filtered = printings.filter { category.setCodes.contains($0.set.code) }
                if let card = filtered.first {
                    resolvedCards[name] = card
                    return
                }
            }
        }

        // Fallback: standard resolution via CardResolver
        let resolver = CardResolver(cardRepository: cardRepository)
        if let card = await resolver.resolve(name: name) {
            resolvedCards[name] = card
        }
    }
}
