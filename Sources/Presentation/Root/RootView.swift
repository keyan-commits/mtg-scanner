import SwiftUI

/// Top-level navigation shell. Five tabs at the bottom — Home, Scan,
/// Decks, Collection, Shop. Each tab owns its own NavigationStack so
/// drill-downs don't leak across tabs.
struct RootView: View {

    let viewModel: CardScannerViewModel
    let pipeline: CardIdentificationPipelineProtocol
    let repository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var selectedTab: Tab = .home

    enum Tab: Hashable {
        case home, scan, decks, collection, shop
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    deckRepository: deckRepository,
                    cardRepository: repository,
                    onScanTap: { selectedTab = .scan }
                )
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(Tab.home)

            NavigationStack {
                ScannerScreen(
                    viewModel: viewModel,
                    pipeline: pipeline,
                    repository: repository,
                    deckRepository: deckRepository
                )
            }
            .tabItem { Label("Scan", systemImage: "viewfinder") }
            .tag(Tab.scan)

            NavigationStack {
                DecksScreen(repository: deckRepository, cardRepository: repository)
            }
            .tabItem { Label("Decks", systemImage: "rectangle.stack.fill") }
            .tag(Tab.decks)

            NavigationStack {
                CollectionScreen(deckRepository: deckRepository, cardRepository: repository)
            }
            .tabItem { Label("Collection", systemImage: "tray.full.fill") }
            .tag(Tab.collection)

            NavigationStack {
                ShopView(deckRepository: deckRepository, cardRepository: repository)
            }
            .tabItem { Label("Shop", systemImage: "cart.fill") }
            .tag(Tab.shop)
        }
        .tint(MD3Theme.primary)
        .task {
            // Pre-load exchange rates once at app launch so every screen
            // that displays converted prices has data ready. No-op within
            // the 24h cache window.
            await CurrencyService.shared.refreshIfStale()
        }
    }
}
