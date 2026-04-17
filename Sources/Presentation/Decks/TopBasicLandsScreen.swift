import SwiftUI

/// Shows the top 100 most expensive basic lands across all sets.
struct TopBasicLandsScreen: View {

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
                ProgressView("Loading basic lands...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if topCards.isEmpty {
                ContentUnavailableView(
                    "No Priced Lands",
                    systemImage: "leaf.circle",
                    description: Text("No basic lands with USD pricing found.")
                )
            } else {
                switch viewMode {
                case .list: listBody
                case .grid: gridBody
                }
            }
        }
        .navigationTitle("Top 100 Basic Lands")
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
        .task { await loadTopLands() }
    }

    // MARK: - List

    private var listBody: some View {
        List {
            Section {
                Text("Most expensive basic lands across all expansions")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .listRowBackground(Color.clear)
            }
            Section("\(topCards.count) lands") {
                ForEach(Array(topCards.enumerated()), id: \.element.id) { index, card in
                    NavigationLink {
                        CardListPagerView(
                            cards: topCards,
                            initialIndex: index,
                            cardRepository: cardRepository,
                            deckRepository: deckRepository
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
            Text("#\(rank)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(rankColor(rank))
                .clipShape(Circle())

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
                Text(card.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(card.setNameWithYear)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .lineLimit(1)
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
                        CardListPagerView(
                            cards: topCards,
                            initialIndex: index,
                            cardRepository: cardRepository,
                            deckRepository: deckRepository
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
                            RoundedRectangle(cornerRadius: 6)
                                .fill(MD3Theme.surfaceVariant)
                                .aspectRatio(63.0 / 88.0, contentMode: .fit)
                        }
                    }
                }
                Text("#\(rank)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(rankColor(rank))
                    .clipShape(Capsule())
                    .offset(x: -2, y: -2)
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
                    .lineLimit(1)
                if let usd = card.prices.usd {
                    Text("$\(usd)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MD3Theme.primary)
                        .monospacedDigit()
                }
            }
        }
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

    private func loadTopLands() async {
        guard topCards.isEmpty else { return }
        let lands = (try? await cardRepository.fetchBasicLands()) ?? []
        topCards = lands
            .filter { $0.prices.usd != nil }
            .sorted { a, b in
                let pa = Double(a.prices.usd ?? "0") ?? 0
                let pb = Double(b.prices.usd ?? "0") ?? 0
                return pa > pb
            }
            .prefix(100)
            .map { $0 }
        ownedQuantities = (try? deckRepository.ownedQuantitiesByName()) ?? [:]
        isLoading = false
    }
}
