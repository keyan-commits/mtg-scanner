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
                    categoryRow(category, in: LandLists.all)
                }
            }
            Section("Collectible Lands") {
                ForEach(CollectibleLands.all) { category in
                    categoryRow(category, in: CollectibleLands.all)
                }
            }
            Section("cEDH Staples") {
                ForEach(CEDHStaples.all) { category in
                    categoryRow(category, in: CEDHStaples.all)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryRow(_ category: LandCategory, in categories: [LandCategory]) -> some View {
        let index = categories.firstIndex(where: { $0.id == category.id }) ?? 0
        return NavigationLink {
            LandSectionPagerView(
                categories: categories,
                initialIndex: index,
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

// MARK: - Section Pager View

/// Horizontal pager that wraps category detail views, letting the user
/// swipe left/right to browse adjacent categories within a section.
struct LandSectionPagerView: View {

    let categories: [LandCategory]
    let initialIndex: Int
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var currentIndex: Int = 0
    @State private var viewMode: ViewMode = .grid
    @State private var sortByPrice: Bool = false

    enum ViewMode: String, CaseIterable, Hashable {
        case list, grid
        var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                LandCategoryDetailView(
                    category: category,
                    viewMode: viewMode,
                    sortByPrice: sortByPrice,
                    cardRepository: cardRepository,
                    deckRepository: deckRepository
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .onAppear { currentIndex = initialIndex }
        .navigationTitle(categories.indices.contains(currentIndex) ? categories[currentIndex].name : "")
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
    }
}

// MARK: - Category Detail View

/// Shows all cards in a land category with list/visual toggle.
/// Each card is resolved via `CardResolver` (honoring the user's
/// Default Printing setting) and tappable -> `CardDetailView`.
/// Categories with `setCodes` show ALL printings from those sets.
struct LandCategoryDetailView: View {

    let category: LandCategory
    let viewMode: LandSectionPagerView.ViewMode
    let sortByPrice: Bool
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    /// Resolved cards keyed by card name. Each name may have multiple
    /// printings when the category specifies `setCodes`.
    @State private var resolvedCards: [String: [Card]] = [:]
    @State private var ownedByName: [String: Int] = [:]
    @State private var ownedDetails: [String: [(setCode: String, setName: String, quantity: Int)]] = [:]

    /// All resolved cards flattened in display order.
    private var sortedCards: [Card] {
        let flat = category.cardNames.flatMap { name -> [Card] in
            (resolvedCards[name] ?? []).sorted { $0.collectorNumber < $1.collectorNumber }
        }
        guard sortByPrice else { return flat }
        return flat.sorted { a, b in
            let pa = Double(a.prices.usd ?? "") ?? -1
            let pb = Double(b.prices.usd ?? "") ?? -1
            return pa > pb
        }
    }

    private var allResolved: Bool {
        category.cardNames.allSatisfy { resolvedCards[$0] != nil }
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
        .task {
            ownedByName = (try? deckRepository.ownedQuantitiesByName()) ?? [:]
            ownedDetails = (try? deckRepository.ownedDetailsByName()) ?? [:]
            await resolveAll()
        }
    }

    // MARK: - Resolution

    private func resolveAll() async {
        for name in category.cardNames {
            guard resolvedCards[name] == nil else { continue }

            if !category.setCodes.isEmpty {
                if let printings = try? await cardRepository.findAllPrintings(name: name) {
                    let filtered = printings.filter { category.setCodes.contains($0.set.code) }
                    if !filtered.isEmpty {
                        resolvedCards[name] = filtered
                        continue
                    }
                }
            }

            // Fallback: standard resolution via CardResolver
            let resolver = CardResolver(cardRepository: cardRepository)
            if let card = await resolver.resolve(name: name) {
                resolvedCards[name] = [card]
            }
        }
    }

    // MARK: - Ownership

    private enum OwnershipStatus {
        case exactMatch(Int)
        case differentSet([(setName: String, quantity: Int)])
        case notOwned
    }

    private func ownershipStatus(for card: Card) -> OwnershipStatus {
        let name = card.name
        let details = ownedDetails[name] ?? []

        if !category.setCodes.isEmpty {
            // Collectible lands: check exact set+collector match
            let exactQty = details
                .filter { $0.setCode == card.set.code }
                .reduce(0) { $0 + $1.quantity }
            return exactQty > 0 ? .exactMatch(exactQty) : .notOwned
        }

        // Normal lists: check if owned in any printing
        let totalOwned = ownedByName[name] ?? 0
        guard totalOwned > 0 else { return .notOwned }

        let matchingQty = details
            .filter { $0.setCode == card.set.code }
            .reduce(0) { $0 + $1.quantity }
        if matchingQty > 0 { return .exactMatch(matchingQty) }

        let setDetails = details.map { (setName: $0.setName, quantity: $0.quantity) }
        return .differentSet(setDetails)
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
            Section("\(sortedCards.count) cards") {
                let cards = sortedCards
                ForEach(Array(cards.enumerated()), id: \.element.scryfallID) { index, card in
                    NavigationLink {
                        LandCardPagerView(
                            cards: cards,
                            initialIndex: index,
                            cardRepository: cardRepository,
                            deckRepository: deckRepository
                        )
                    } label: {
                        listRow(card: card)
                    }
                }
                if !allResolved {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading\u{2026}")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func listRow(card: Card) -> some View {
        let status = ownershipStatus(for: card)
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
            case .differentSet:
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 10, weight: .bold))
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
                    Text(card.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)
                    if let manaCost = card.manaCost, !manaCost.isEmpty {
                        ManaCostView(cost: manaCost, size: 12)
                    }
                }
                Text("\(card.setNameWithYear) \u{00B7} #\(card.collectorNumber)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                if case .differentSet(let sets) = status {
                    let summary = sets.map { "\($0.quantity)x \($0.setName)" }.joined(separator: ", ")
                    Text("Owned: \(summary)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let usd = card.prices.usd {
                Text("$\(usd)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.primary)
                    .monospacedDigit()
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

                let cards = sortedCards
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(Array(cards.enumerated()), id: \.element.scryfallID) { index, card in
                        NavigationLink {
                            LandCardPagerView(
                                cards: cards,
                                initialIndex: index,
                                cardRepository: cardRepository,
                                deckRepository: deckRepository
                            )
                        } label: {
                            gridCardLabel(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                if !allResolved {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                }

                Color.clear.frame(height: 24)
            }
        }
        .background(MD3Theme.background)
    }

    private func gridCardLabel(card: Card) -> some View {
        let status = ownershipStatus(for: card)
        return VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let urlString = card.imageURIs["normal"]
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
                            gridPlaceholder(card.name)
                        }
                    }
                } else {
                    gridPlaceholder(card.name)
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
                case .differentSet:
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.orange)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                case .notOwned:
                    EmptyView()
                }
            }
            Text(card.name)
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
}

// MARK: - Card Pager View

/// Horizontal paging view that wraps `CardDetailView` instances,
/// letting the user swipe left/right to browse cards in a land category.
struct LandCardPagerView: View {

    let cards: [Card]
    let initialIndex: Int
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var currentIndex: Int = 0

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(cards.enumerated()), id: \.element.scryfallID) { index, card in
                CardDetailView(
                    card: card,
                    repository: cardRepository,
                    deckRepository: deckRepository,
                    onScanAnother: {}
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .onAppear { currentIndex = initialIndex }
        .navigationTitle(cards.indices.contains(currentIndex) ? cards[currentIndex].name : "")
        .navigationBarTitleDisplayMode(.inline)
    }
}
