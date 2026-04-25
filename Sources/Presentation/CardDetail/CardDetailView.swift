import SwiftUI

// MARK: - Card Detail View

/// Displays detailed information about an identified Magic card,
/// including its image, name, set, price, format legality, and oracle text.
struct CardDetailView: View {

    @State private var viewModel: CardDetailViewModel
    private let onScanAnother: () -> Void
    private let repository: CardRepositoryProtocol?
    private let deckRepository: DeckListRepository?
    private let onCorrection: ((Card) -> Void)?

    @State private var showCorrection = false
    @State private var otherPrintings: [Card] = []
    @State private var isFirstPrint: Bool = false
    @State private var firstPrintScryfallID: String?
    @State private var printingsSortAscending: Bool = true
    @State private var showAllPrintings = false
    @State private var showAddToDeck = false
    @State private var showAddToCollection = false
    @State private var rulings: [CardRuling] = []
    @State private var rulingsState: RulingsState = .idle
    @State private var phListings: [TCGPHListing] = []
    @State private var phLoading = false
    @State private var phURL: String?

    private enum RulingsState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    private let rulingsService: CardRulingsServiceProtocol = CardRulingsService.shared

    /// Shared across all CardDetailView instances so MTGTop8 results
    /// are cached process-wide instead of re-fetched per card.
    private static let sharedDeckLookupService: DeckLookupServiceProtocol = DeckLookupService(
        mtgTop8Service: MTGTop8Service(),
        edhrecService: EDHRECService()
    )

    /// Creates a card detail view.
    /// - Parameters:
    ///   - card: The card to display.
    ///   - repository: Optional repository for card correction search.
    ///   - deckRepository: Optional repository for adding the card to a deck.
    ///   - onCorrection: Optional callback when the user corrects the card.
    ///   - onScanAnother: Closure invoked when the user taps "Scan Another".
    init(
        card: Card,
        repository: CardRepositoryProtocol? = nil,
        deckRepository: DeckListRepository? = nil,
        onCorrection: ((Card) -> Void)? = nil,
        onScanAnother: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: CardDetailViewModel(card: card))
        self.repository = repository
        self.deckRepository = deckRepository
        self.onCorrection = onCorrection
        self.onScanAnother = onScanAnother
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                cardImage
                cardHeader
                cardListTags
                PriceComparisonView(card: viewModel.card)
                phStoresSection
                otherPrintingsSection
                classicArchetypesSection
                legalitySection
                DeckCompatibilityView(
                    card: viewModel.card,
                    deckLookupService: Self.sharedDeckLookupService,
                    cardRepository: repository,
                    deckRepository: deckRepository
                )
                oracleTextSection
                rulingsSection
                addToDeckButton
                addToCollectionButton
                scanAnotherButton
            }
            .padding(16)
        }
        .background(MD3Theme.background)
        .task {
            await loadVariantInfo()
        }
        .task(id: viewModel.card.scryfallID) {
            await loadPHListings()
        }
        .task(id: viewModel.card.scryfallID) {
            // Refetches rulings when the user swaps to a different
            // printing via the Other Printings list (the view model's
            // card mutates in place rather than spawning a new view).
            await loadRulings()
        }
        .sheet(isPresented: $showAddToDeck) {
            if let deckRepository {
                AddToDeckSheet(card: viewModel.card, repository: deckRepository) {
                    showAddToDeck = false
                }
            }
        }
        .sheet(isPresented: $showAddToCollection) {
            if let deckRepository {
                QuickAddToCollectionSheet(
                    card: viewModel.card,
                    deckRepository: deckRepository
                ) {
                    showAddToCollection = false
                }
            }
        }
    }

    @ViewBuilder
    private var addToDeckButton: some View {
        if deckRepository != nil {
            MD3FilledButton("Add to Deck") {
                showAddToDeck = true
            }
        }
    }

    @ViewBuilder
    private var addToCollectionButton: some View {
        if deckRepository != nil {
            MD3OutlinedButton("Add to Collection") {
                showAddToCollection = true
            }
        }
    }

    // MARK: - Card Image

    @State private var showFullImage = false

    private var cardImage: some View {
        Group {
            if let url = viewModel.cardImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { showFullImage = true }
                    case .failure:
                        imagePlaceholder
                    case .empty:
                        ProgressView()
                            .frame(height: 340)
                    @unknown default:
                        imagePlaceholder
                    }
                }
                .frame(maxHeight: 340)
            } else {
                imagePlaceholder
            }
        }
        .fullScreenCover(isPresented: $showFullImage) {
            if let url = viewModel.cardImageURL {
                fullImageView(url: url)
            }
        }
    }

    private func fullImageView(url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .ignoresSafeArea()
                default:
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                showFullImage = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(20)
            }
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(MD3Theme.surfaceVariant)
            .frame(height: 340)
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.card.name)
                .font(MD3Typography.headlineMedium)
                .foregroundStyle(MD3Theme.onBackground)

            if let printedName = viewModel.card.printedName,
               printedName != viewModel.card.name {
                Text(printedName)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

            HStack(spacing: 6) {
                Text("\(viewModel.card.setNameWithYear) \u{2022} #\(viewModel.card.collectorNumber)")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)

                Text(rarityLabel(viewModel.card.rarity))
                    .font(MD3Typography.labelMedium)
                    .foregroundStyle(rarityColor(viewModel.card.rarity))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(rarityColor(viewModel.card.rarity).opacity(0.15))
                    .clipShape(Capsule())

                if let variant = viewModel.variantLabel {
                    Text(variant)
                        .font(MD3Typography.labelMedium)
                        .foregroundStyle(MD3Theme.onTertiaryContainer)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(MD3Theme.tertiaryContainer)
                        .clipShape(Capsule())
                }

                if isFirstPrint {
                    Text("First Print")
                        .font(MD3Typography.labelMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }

                if let lang = viewModel.card.lang, lang != "en" {
                    Text(lang.uppercased())
                        .font(MD3Typography.labelMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }

            if let artist = viewModel.artistLabel {
                Text(artist)
                    .font(MD3Typography.bodySmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

            if onCorrection != nil, repository != nil {
                Button {
                    showCorrection = true
                } label: {
                    Text("Wrong card? Tap to correct")
                        .font(MD3Typography.labelLarge)
                        .foregroundStyle(MD3Theme.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(MD3Theme.outline, lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showCorrection) {
            if let repository, let onCorrection {
                CardCorrectionView(
                    repository: repository,
                    currentCard: viewModel.card,
                    onCorrection: { correctedCard in
                        showCorrection = false
                        onCorrection(correctedCard)
                    }
                )
            }
        }
    }

    // MARK: - Card List Tags

    /// Compact capsule tags showing which curated lists contain this card.
    /// Only checks card-name–based lists (not expansion-specific ones like
    /// Guru Lands or Zendikar Expeditions which filter by set code).
    @ViewBuilder
    private var cardListTags: some View {
        let name = viewModel.card.name
        let tags = Self.computeListTags(for: name)
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Appears In")
                    .font(MD3Typography.titleSmall)
                    .foregroundStyle(MD3Theme.onSurface)
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MD3Theme.onSecondaryContainer)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MD3Theme.secondaryContainer)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Computes all list memberships for a card by name.
    /// Excludes expansion-specific categories (those with non-empty setCodes).
    private static func computeListTags(for cardName: String) -> [String] {
        var tags: [String] = []
        let lowered = cardName.lowercased()

        // Land type categories (Fetch, Shock, Dual, etc.) — no setCodes
        for cat in LandLists.all where cat.setCodes.isEmpty {
            if cat.cardNames.contains(where: { $0.lowercased() == lowered }) {
                tags.append(cat.name)
            }
        }

        // Reserved List
        for cat in ReservedList.all {
            if cat.cardNames.contains(where: { $0.lowercased() == lowered }) {
                tags.append("Reserved List")
                break
            }
        }

        // Format Staples (hardcoded curated lists)
        let stapleFormats: [(String, [LandCategory])] = [
            ("Modern Staple", ModernStaples.all),
            ("Legacy Staple", LegacyStaples.all),
            ("Pioneer Staple", PioneerStaples.all),
            ("Vintage Staple", VintageStaples.all),
            ("Pauper Staple", PauperStaples.all),
            ("Premodern Staple", PremodernStaples.all),
            ("Standard Staple", StandardStaples.all),
            ("cEDH Staple", CEDHStaples.all),
        ]
        for (label, categories) in stapleFormats {
            for cat in categories {
                if cat.cardNames.contains(where: { $0.lowercased() == lowered }) {
                    tags.append(label)
                    break
                }
            }
        }

        return tags
    }

    // MARK: - Classic Archetypes Section

    /// Lists every hand-curated classic deck (from `ClassicArchetypes`) that
    /// plays this card. Lets the user discover that the card they just
    /// scanned is a piece of a famous historical deck.
    @ViewBuilder
    private var classicArchetypesSection: some View {
        let cardName = viewModel.card.name.lowercased()
        let matches = ClassicArchetypes.all.filter { archetype in
            archetype.mainboard.keys.contains { $0.lowercased() == cardName }
                || (archetype.sideboard?.keys.contains { $0.lowercased() == cardName } ?? false)
        }
        if !matches.isEmpty {
            MD3Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Played in Classic Decks")
                            .font(MD3Typography.titleMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                        Spacer()
                        Text("\(matches.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                    ForEach(matches) { archetype in
                        if let repo = repository, let deckRepo = deckRepository {
                            NavigationLink {
                                ClassicDeckDetailView(
                                    archetype: archetype,
                                    deckRepository: deckRepo,
                                    cardRepository: repo
                                )
                            } label: {
                                archetypeRow(archetype, cardName: cardName)
                            }
                        } else {
                            archetypeRow(archetype, cardName: cardName)
                        }
                        if archetype.id != matches.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func archetypeRow(_ archetype: ClassicArchetype, cardName: String) -> some View {
        let mainQty = archetype.mainboard.first { $0.key.lowercased() == cardName }?.value ?? 0
        let sideQty = archetype.sideboard?.first { $0.key.lowercased() == cardName }?.value ?? 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(archetype.name)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Text("\(archetype.format) · \(archetype.era)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            Spacer()
            HStack(spacing: 4) {
                if mainQty > 0 {
                    Text("\(mainQty)×")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MD3Theme.primary)
                        .monospacedDigit()
                }
                if sideQty > 0 {
                    Text("(SB \(sideQty))")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - PH Stores (tcgph.com)

    @ViewBuilder
    private var phStoresSection: some View {
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
        } else if !phListings.isEmpty {
            MD3Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("PH Stores")
                            .font(MD3Typography.titleMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                        Spacer()
                        Text("\(phListings.count) listing\(phListings.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }

                    ForEach(phListings) { listing in
                        phListingRow(listing)
                        if listing.id != phListings.last?.id {
                            Divider()
                        }
                    }

                    HStack(spacing: 16) {
                        if let phURL, let url = URL(string: phURL) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.caption)
                                    Text("tcgph.com")
                                }
                                .font(MD3Typography.labelLarge)
                                .foregroundStyle(MD3Theme.primary)
                            }
                        }
                        Spacer()
                        // MTG Tambayan FB Group search link
                        if let tambayURL = mtgTambayURL {
                            Link(destination: tambayURL) {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.3.fill")
                                        .font(.caption)
                                    Text("MTG Tambayan")
                                }
                                .font(MD3Typography.labelLarge)
                                .foregroundStyle(.blue)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    Text("Prices in PHP from tcgph.com (17 PH stores)")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .padding(16)
            }
        } else if !phLoading {
            // Always show PH section with search links
            MD3Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PH Stores")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    Text("No listings found on tcgph.com")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)

                    HStack(spacing: 16) {
                        // tcgph.com search
                        let slug = viewModel.card.name.lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                            .replacingOccurrences(of: ",", with: "")
                            .replacingOccurrences(of: "'", with: "")
                        if let url = URL(string: "https://tcgph.com/card/\(slug)") {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.caption)
                                    Text("tcgph.com")
                                }
                                .font(MD3Typography.labelLarge)
                                .foregroundStyle(MD3Theme.primary)
                            }
                        }
                        Spacer()
                        if let tambayURL = mtgTambayURL {
                            Link(destination: tambayURL) {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.3.fill")
                                        .font(.caption)
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

    private func phListingRow(_ listing: TCGPHListing) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.storeName)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(listing.condition)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(conditionColor(listing.condition))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(conditionColor(listing.condition).opacity(0.15))
                        .clipShape(Capsule())
                    if listing.quantity > 1 {
                        Text("\(listing.quantity) avail")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
            }
            Spacer()
            Text("\u{20B1}\(String(format: "%.0f", listing.price))")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.primary)
                .monospacedDigit()
            if let url = URL(string: listing.storeURL) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// URL for searching the card on MTG Tambayan Facebook group.
    private var mtgTambayURL: URL? {
        let query = viewModel.card.name
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.facebook.com/groups/135914699791891/search/?q=\(query)")
    }

    private func conditionColor(_ condition: String) -> Color {
        switch condition {
        case "NM": return .green
        case "LP": return .yellow
        case "MP": return .orange
        case "HP", "DMG": return .red
        default: return .gray
        }
    }

    private func loadPHListings() async {
        phLoading = true
        phListings = []
        phURL = nil
        let card = viewModel.card
        let result = await TCGPHService.shared.fetchListings(
            setCode: card.set.code,
            collectorNumber: card.collectorNumber,
            cardName: card.name
        )
        phListings = result?.listings ?? []
        phURL = result?.tcgphURL
        phLoading = false
    }

    // MARK: - Legality Section

    private var legalitySection: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Format Legality")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)

                ForEach(viewModel.legalFormats, id: \.0) { format, status in
                    HStack {
                        Circle()
                            .fill(legalityColor(for: status))
                            .frame(width: 10, height: 10)

                        Text(format)
                            .font(MD3Typography.bodyMedium)
                            .foregroundStyle(MD3Theme.onSurface)

                        Spacer()

                        Text(legalityLabel(for: status))
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(legalityColor(for: status))
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Oracle Text

    @ViewBuilder
    private var oracleTextSection: some View {
        if let oracleText = viewModel.card.oracleText, !oracleText.isEmpty {
            MD3Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Oracle Text")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    Text(oracleText)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Rules & Rulings

    /// Live-fetched ruling list from Scryfall (judge clarifications,
    /// errata, interaction notes). Cached in-session per scryfallID
    /// via `CardRulingsService.shared`. Renders nothing for cards
    /// with no rulings — most cards never get ruling activity.
    @ViewBuilder
    private var rulingsSection: some View {
        switch rulingsState {
        case .idle:
            EmptyView()
        case .loading:
            MD3Card {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading rulings…")
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .error(let message):
            MD3Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rules & Rulings")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                    Text(message)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(.orange)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .loaded:
            if rulings.isEmpty {
                EmptyView()
            } else {
                MD3Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Rules & Rulings")
                                .font(MD3Typography.titleMedium)
                                .foregroundStyle(MD3Theme.onSurface)
                            Spacer()
                            Text("\(rulings.count)")
                                .font(.caption2)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                        Text("Official judge clarifications and interaction notes from Scryfall.")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        ForEach(rulings) { ruling in
                            rulingRow(ruling)
                            if ruling.id != rulings.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func rulingRow(_ ruling: CardRuling) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ruling.comment)
                .font(MD3Typography.bodySmall)
                .foregroundStyle(MD3Theme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(ruling.source.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MD3Theme.primary)
                Text(ruling.publishedAt)
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        }
    }

    private func loadRulings() async {
        rulingsState = .loading
        do {
            let result = try await rulingsService.rulings(forScryfallID: viewModel.card.scryfallID)
            rulings = result
            rulingsState = .loaded
        } catch {
            // Don't show an error for the empty case (most cards have
            // no rulings) — only surface real failures.
            rulings = []
            rulingsState = .loaded
        }
    }

    // MARK: - Scan Another Button

    private var scanAnotherButton: some View {
        MD3OutlinedButton("Identify Another") {
            onScanAnother()
        }
        .padding(.top, 8)
    }

    // MARK: - Other Printings

    private var otherPrintingsSection: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Other Printings")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    Spacer()

                    if !otherPrintings.isEmpty {
                        Text("\(otherPrintings.count)")
                            .font(MD3Typography.labelSmall)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)

                        Button {
                            printingsSortAscending.toggle()
                        } label: {
                            Image(systemName: printingsSortAscending ? "arrow.up" : "arrow.down")
                                .font(.caption)
                                .foregroundStyle(MD3Theme.primary)
                        }
                    }
                }

                if otherPrintings.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    let sorted = printingsSortAscending ? otherPrintings : otherPrintings.reversed()
                    let displayed = showAllPrintings ? Array(sorted) : Array(sorted.prefix(5))

                    ForEach(displayed) { printing in
                        Button {
                            // Swap the displayed card in-place. The view
                            // re-renders with the new printing's data —
                            // no new screen, no stack.
                            viewModel.swap(to: printing)
                            // Re-fetch other printings for the new card
                            // (will dedupe out the now-current one).
                            Task { await loadOtherPrintings() }
                        } label: {
                            HStack(spacing: 8) {
                                if let urlString = printing.imageURIs["small"],
                                   let url = URL(string: urlString) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        default:
                                            RoundedRectangle(cornerRadius: 3).fill(MD3Theme.surfaceVariant)
                                        }
                                    }
                                    .frame(width: 32, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(printing.setNameWithYear)
                                            .font(MD3Typography.bodySmall)
                                            .foregroundStyle(MD3Theme.onSurface)
                                            .lineLimit(1)
                                        if printing.scryfallID == firstPrintScryfallID {
                                            Text("First Print")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.blue)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text("#\(printing.collectorNumber)")
                                        .font(MD3Typography.labelSmall)
                                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                                }

                                Spacer()

                                if let usd = printing.prices.usd {
                                    Text("$\(usd)")
                                        .font(MD3Typography.labelMedium)
                                        .foregroundStyle(MD3Theme.primary)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if otherPrintings.count > 5 && !showAllPrintings {
                        Button {
                            showAllPrintings = true
                        } label: {
                            Text("Show all \(otherPrintings.count) printings")
                                .font(MD3Typography.labelLarge)
                                .foregroundStyle(MD3Theme.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(16)
        }
        .task {
            await loadOtherPrintings()
        }
    }

    private func loadOtherPrintings() async {
        guard let repository else { return }
        do {
            let all = try await repository.findAllPrintings(name: viewModel.card.name)
            // Exclude the printing currently being viewed. Card identity
            // is the Scryfall printing ID, so this is now stable across
            // separate fetches.
            otherPrintings = all
                .filter { $0 != viewModel.card }
                .sorted { ($0.releasedAt ?? "9999") < ($1.releasedAt ?? "9999") }

            // Determine if this is the first print (earliest release date)
            let earliest = all.min { a, b in
                (a.releasedAt ?? "9999") < (b.releasedAt ?? "9999")
            }
            isFirstPrint = earliest?.scryfallID == viewModel.card.scryfallID
            firstPrintScryfallID = earliest?.scryfallID
        } catch {
            otherPrintings = []
        }
    }

    // MARK: - Variant Cross-Reference

    private func loadVariantInfo() async {
        // If already has a variant label from collector number suffix, skip
        let number = viewModel.card.collectorNumber
        if let lastChar = number.last, lastChar.isLetter { return }

        // Cross-reference illustration_id to find matching variant in another set
        guard let illustrationID = viewModel.card.illustrationID else { return }

        do {
            // Use the repository to find cards by illustration ID instead of
            // creating a fresh DatabaseManager (which is wasteful per-view).
            let sameArt = (try? await repository?.findAllPrintings(name: viewModel.card.name)) ?? []

            // Look for a matching card with a letter suffix collector number
            let knownNames: [String: [String: String]] = [
                "Mishra's Factory": ["a": "Spring", "b": "Summer", "c": "Autumn", "d": "Winter"],
                "Urza's Mine": ["a": "Pulley", "b": "Mouth", "c": "Clawed Sphere", "d": "Tower"],
                "Urza's Power Plant": ["a": "Sphere", "b": "Columns", "c": "Bug", "d": "Rock in Pot"],
                "Urza's Tower": ["a": "Forest", "b": "Shore", "c": "Plains", "d": "Mountains"],
                "Strip Mine": ["a": "No Horizon", "b": "Even Horizon", "c": "Tower", "d": "Uneven Horizon"],
            ]

            for record in sameArt {
                if let lastChar = record.collectorNumber.last, lastChar.isLetter {
                    let suffix = String(lastChar).lowercased()
                    let cardName = viewModel.card.name
                    if let named = knownNames[cardName]?[suffix] {
                        viewModel.crossReferencedVariant = named
                    } else if let artist = viewModel.card.artist {
                        let parts = artist.split(separator: " ")
                        viewModel.crossReferencedVariant = parts.last.map(String.init) ?? "Variant \(suffix.uppercased())"
                    } else {
                        viewModel.crossReferencedVariant = "Variant \(suffix.uppercased())"
                    }
                    return
                }
            }
        } catch {
            // Cross-reference failed, no variant label
        }
    }

    // MARK: - Rarity

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

    // MARK: - Helpers

    private func legalityColor(for status: LegalityStatus) -> Color {
        switch status {
        case .legal:
            return .green
        case .banned:
            return .red
        case .restricted:
            return .orange
        case .notLegal:
            return .gray
        }
    }

    private func legalityLabel(for status: LegalityStatus) -> String {
        switch status {
        case .legal:
            return "Legal"
        case .banned:
            return "Banned"
        case .restricted:
            return "Restricted"
        case .notLegal:
            return "Not Legal"
        }
    }
}
