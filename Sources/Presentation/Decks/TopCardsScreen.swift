import SwiftUI

/// Browse sets/expansions and see the top 10 most expensive cards in each.
/// Prices are per-printing (not affected by Default Printing setting).
struct TopCardsScreen: View {

    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var allSets: [SetInfo] = []
    @State private var searchText: String = ""
    @State private var selectedGroup: SetGroup = .expansion
    @State private var isLoading = true

    /// Grouping by set type.
    enum SetGroup: String, CaseIterable, Identifiable {
        case expansion = "Expansions"
        case core = "Core Sets"
        case masters = "Masters & Reprint"
        case other = "Other"
        var id: String { rawValue }
    }

    private func group(for setType: String) -> SetGroup {
        switch setType {
        case "expansion": return .expansion
        case "core": return .core
        case "masters", "draft_innovation": return .masters
        default: return .other
        }
    }

    private var filteredSets: [SetInfo] {
        let grouped = allSets.filter { group(for: $0.setType) == selectedGroup }
        if searchText.isEmpty { return grouped }
        let query = searchText.lowercased()
        return grouped.filter {
            $0.name.lowercased().contains(query) || $0.code.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading sets...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Group picker
                Picker("", selection: $selectedGroup) {
                    ForEach(SetGroup.allCases) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    ForEach(filteredSets, id: \.code) { setInfo in
                        NavigationLink {
                            TopCardsDetailView(
                                setInfo: setInfo,
                                cardRepository: cardRepository,
                                deckRepository: deckRepository
                            )
                        } label: {
                            setRow(setInfo)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Top Cards")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search sets...")
        .task { await loadSets() }
    }

    private func setRow(_ set: SetInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForSetType(set.setType))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MD3Theme.primary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(set.code.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(MD3Theme.primary.opacity(0.7))
                    if let year = set.releasedAt?.prefix(4) {
                        Text(String(year))
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
        }
        .padding(.vertical, 4)
    }

    private func iconForSetType(_ type: String) -> String {
        switch type {
        case "expansion": return "flame.fill"
        case "core": return "star.fill"
        case "masters", "draft_innovation": return "crown.fill"
        default: return "square.stack.fill"
        }
    }

    private func loadSets() async {
        guard allSets.isEmpty else { return }
        let sets = (try? await cardRepository.fetchAllSets()) ?? []
        // Sort by release date descending (newest first)
        allSets = sets.sorted { a, b in
            (a.releasedAt ?? "0000") > (b.releasedAt ?? "0000")
        }
        isLoading = false
    }
}

// MARK: - Top Cards Detail View

/// Shows the top 10 most expensive cards in a set with list/grid toggle.
/// Prices are per-printing — not affected by the Default Printing setting.
struct TopCardsDetailView: View {

    let setInfo: SetInfo
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var topCards: [Card] = []
    @State private var isLoading = true
    @State private var viewMode: ViewMode = .list
    @State private var ownedQuantities: [String: Int] = [:]

    private enum ViewMode: String, CaseIterable, Hashable {
        case list, grid
        var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading cards...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if topCards.isEmpty {
                ContentUnavailableView(
                    "No Priced Cards",
                    systemImage: "dollarsign.circle",
                    description: Text("No cards with USD pricing in this set.")
                )
            } else {
                switch viewMode {
                case .list: listBody
                case .grid: gridBody
                }
            }
        }
        .navigationTitle(setInfo.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
        }
        .task { await loadTopCards() }
    }

    // MARK: - List

    private var listBody: some View {
        List {
            Section {
                if let year = setInfo.releasedAt?.prefix(4) {
                    Text("Top 10 most expensive cards in \(setInfo.name) (\(year))")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .listRowBackground(Color.clear)
                } else {
                    Text("Top 10 most expensive cards in \(setInfo.name)")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .listRowBackground(Color.clear)
                }
            }
            Section("\(topCards.count) cards") {
                ForEach(Array(topCards.enumerated()), id: \.element.id) { index, card in
                    NavigationLink {
                        CardDetailView(
                            card: card,
                            repository: cardRepository,
                            deckRepository: deckRepository,
                            onScanAnother: {}
                        )
                    } label: {
                        listRow(rank: index + 1, card: card)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func listRow(rank: Int, card: Card) -> some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("#\(rank)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(rankColor(rank))
                .clipShape(Circle())

            // Owned quantity
            let owned = ownedQuantities[card.name] ?? 0
            if owned > 0 {
                Text("\(owned)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.green)
                    .clipShape(Circle())
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
                HStack(spacing: 6) {
                    Text(card.rarity.rawValue.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(rarityColor(card.rarity))
                    Text("#\(card.collectorNumber)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
            Spacer(minLength: 8)
            if let usd = card.prices.usd {
                Text("$\(usd)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MD3Theme.primary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Grid

    private var gridBody: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Array(topCards.enumerated()), id: \.element.id) { index, card in
                    NavigationLink {
                        CardDetailView(
                            card: card,
                            repository: cardRepository,
                            deckRepository: deckRepository,
                            onScanAnother: {}
                        )
                    } label: {
                        gridCard(rank: index + 1, card: card)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Color.clear.frame(height: 24)
        }
        .background(MD3Theme.background)
    }

    private func gridCard(rank: Int, card: Card) -> some View {
        let owned = ownedQuantities[card.name] ?? 0
        return VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
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
                // Rank badge
                Text("#\(rank)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(rankColor(rank))
                    .clipShape(Capsule())
                    .offset(x: -2, y: -2)
                // Owned badge
                if owned > 0 {
                    Text("\(owned)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.green)
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(x: 4, y: -4)
                }
            }
            VStack(spacing: 1) {
                Text(card.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let usd = card.prices.usd {
                    Text("$\(usd)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MD3Theme.primary)
                        .monospacedDigit()
                }
            }
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

    // MARK: - Helpers

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .yellow.opacity(0.85)
        case 2: return .gray
        case 3: return .brown
        default: return MD3Theme.primary.opacity(0.6)
        }
    }

    private func rarityColor(_ rarity: CardRarity) -> Color {
        switch rarity {
        case .mythic: return .orange
        case .rare: return .yellow.opacity(0.8)
        case .uncommon: return .gray
        case .common: return MD3Theme.onSurfaceVariant
        }
    }

    private func loadTopCards() async {
        guard topCards.isEmpty else { return }
        let cards = (try? await cardRepository.fetchCardsBySet(setCode: setInfo.code)) ?? []
        // Sort by USD price descending, take top 10
        topCards = cards
            .filter { $0.prices.usd != nil }
            .sorted { a, b in
                let pa = Double(a.prices.usd ?? "0") ?? 0
                let pb = Double(b.prices.usd ?? "0") ?? 0
                return pa > pb
            }
            .prefix(10)
            .map { $0 }
        ownedQuantities = (try? deckRepository.ownedQuantitiesByName()) ?? [:]
        isLoading = false
    }
}
