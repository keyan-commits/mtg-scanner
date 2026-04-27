import SwiftUI

/// Rich detail page for an `ArchetypeGroup`.
///
/// Layout (top to bottom):
/// - **Hero header**: tinted icon + display name + variant/format counts
/// - **Intro**: hand-curated overview when available, generic placeholder otherwise
/// - **How to play**: hand-curated strategy paragraphs (only when curated)
/// - **Common cards**: live-aggregated from MTGTop8 across all variants
///   (with list / grid toggle, pull-to-refresh, and a "from N decks"
///    source attribution)
/// - **Variants**: every MTGTop8 archetype that merged into this group,
///   each tappable to open `ArchetypeDecksView` for that specific variant
struct MajorArchetypeDetailView: View {

    let group: ArchetypeGroup
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository
    private let aggregator: CommonCardsAggregatorProtocol

    @State private var aggregation: CommonCardsAggregation?
    @State private var isAggregating: Bool = false
    @State private var aggregationError: String?
    @State private var commonCardsViewMode: CardsViewMode = .list
    @State private var resolvedCards: [String: Card] = [:]
    /// Tracks user-overridden disclosure state. Sections not in
    /// either set fall back to the disclosure block's `defaultExpanded`.
    @State private var expandedSections: Set<String> = []
    @State private var collapsedSections: Set<String> = []

    private enum CardsViewMode: String, CaseIterable {
        case list
        case grid
        var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    init(
        group: ArchetypeGroup,
        cardRepository: CardRepositoryProtocol,
        deckRepository: DeckListRepository,
        aggregator: CommonCardsAggregatorProtocol = CommonCardsAggregator()
    ) {
        self.group = group
        self.cardRepository = cardRepository
        self.deckRepository = deckRepository
        self.aggregator = aggregator
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroHeader
                introSection
                if let curated = group.curated {
                    strategySection(curated)
                }
                commonCardsSection
                variantsSection
                Color.clear.frame(height: 24)
            }
            .padding(16)
        }
        .background(MD3Theme.background)
        .navigationTitle(group.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await aggregateCards(forceRefresh: true)
        }
        .task {
            await aggregateCards(forceRefresh: false)
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(tint.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(group.displayName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                Text("\(group.variants.count) variant\(group.variants.count == 1 ? "" : "s") · \(group.formats.count) format\(group.formats.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                if group.curated != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("Curated guide")
                            .font(.caption2)
                    }
                    .foregroundStyle(.yellow)
                }
            }
            Spacer()
        }
    }

    private var iconName: String {
        group.curated?.iconName ?? "rectangle.stack.fill"
    }

    private var tint: Color {
        group.curated.flatMap { Color(hex: $0.tintHex) } ?? MD3Theme.primary
    }

    // MARK: - Intro

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Overview")
            Text(introText)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurface)
        }
    }

    private var introText: String {
        if let intro = group.curated?.intro {
            return intro
        }
        return "\(group.displayName) is a \(group.variants.count == 1 ? "single" : "family of \(group.variants.count)") archetype\(group.variants.count == 1 ? "" : " variants") tracked across \(group.formats.count) format\(group.formats.count == 1 ? "" : "s") on MTGTop8. Tap any variant below to see its top decks, or scroll down for the most common cards across all variants."
    }

    // MARK: - Strategy

    private func strategySection(_ curated: MajorArchetype) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("How to Play")
            Text(curated.strategy)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Common cards

    private var commonCardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("Common Cards")
                Spacer()
                viewModeToggle
            }
            if isAggregating && aggregation == nil {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Aggregating from \(group.variants.count) variants…")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .padding(.vertical, 16)
            } else if let aggregation,
                      !aggregation.universalCards.isEmpty || !aggregation.perFormatCards.isEmpty {
                commonCardsBody(aggregation)
            } else if let curated = group.curated, !curated.signatureCards.isEmpty {
                // Fallback: hand-curated signature cards.
                Text("Showing hand-curated signature cards (live data unavailable):")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                signatureCardsList(curated.signatureCards)
            } else {
                Text(aggregationError ?? "No card data available yet. Pull down to refresh.")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        }
    }

    private var viewModeToggle: some View {
        Picker("", selection: $commonCardsViewMode) {
            ForEach(CardsViewMode.allCases, id: \.self) { mode in
                Image(systemName: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 100)
    }

    @ViewBuilder
    private func commonCardsBody(_ aggregation: CommonCardsAggregation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aggregated from \(aggregation.sources.count) recent #1-finish deck\(aggregation.sources.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            // Pattern C: collapsible sections.
            // Core (universal across all formats) — expanded by default.
            if !aggregation.universalCards.isEmpty {
                disclosureBlock(
                    sectionKey: "core",
                    title: "Core (all \(aggregation.formatsRepresented.count) format\(aggregation.formatsRepresented.count == 1 ? "" : "s"))",
                    cardCount: aggregation.universalCards.count,
                    cards: aggregation.universalCards,
                    defaultExpanded: true
                )
            }

            // Per-format slices — collapsed by default.
            ForEach(aggregation.perFormatCards) { breakdown in
                disclosureBlock(
                    sectionKey: breakdown.formatCode,
                    title: "\(breakdown.formatName)-specific",
                    cardCount: breakdown.cards.count,
                    cards: breakdown.cards,
                    defaultExpanded: false
                )
            }
        }
    }

    @ViewBuilder
    private func disclosureBlock(
        sectionKey: String,
        title: String,
        cardCount: Int,
        cards: [CommonCardEntry],
        defaultExpanded: Bool
    ) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { isSectionExpanded(sectionKey, defaultExpanded: defaultExpanded) },
                set: { newValue in
                    if newValue {
                        expandedSections.insert(sectionKey)
                        collapsedSections.remove(sectionKey)
                    } else {
                        expandedSections.remove(sectionKey)
                        collapsedSections.insert(sectionKey)
                    }
                }
            )
        ) {
            switch commonCardsViewMode {
            case .list:
                commonCardsList(cards)
            case .grid:
                commonCardsGrid(cards)
            }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
                Text("\(cardCount) card\(cardCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        }
        .tint(MD3Theme.primary)
    }

    private func isSectionExpanded(_ key: String, defaultExpanded: Bool) -> Bool {
        if expandedSections.contains(key) { return true }
        if collapsedSections.contains(key) { return false }
        return defaultExpanded
    }

    private func commonCardsList(_ cards: [CommonCardEntry]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                cardRowDestination(cardName: card.cardName, allCardNames: cards.map(\.cardName)) {
                    HStack(spacing: 10) {
                        Text("\(card.deckCount)×")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MD3Theme.primary)
                            .frame(width: 28, alignment: .trailing)
                        Text(card.cardName)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(MD3Theme.onSurface)
                            .lineLimit(1)
                        Spacer()
                        Text("\(card.totalCopies) copies")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                        if resolvedCards[card.cardName] != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
                        } else {
                            ProgressView().scaleEffect(0.5)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                if idx < cards.count - 1 {
                    Divider()
                }
            }
        }
        .background(MD3Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Wraps a row in a `NavigationLink` to `CardDetailView` when the
    /// card has been resolved against the local DB; otherwise renders
    /// an inert button that triggers resolution. Once resolved the
    /// next render swaps in the live link.
    @ViewBuilder
    private func cardRowDestination<Label: View>(
        cardName: String,
        allCardNames: [String] = [],
        @ViewBuilder label: () -> Label
    ) -> some View {
        if let resolved = resolvedCards[cardName] {
            NavigationLink {
                let allResolved = allCardNames.compactMap { resolvedCards[$0] }
                if allResolved.count > 1,
                   let pos = allResolved.firstIndex(where: { $0.scryfallID == resolved.scryfallID }) {
                    CardListPagerView(
                        cards: allResolved,
                        initialIndex: pos,
                        cardRepository: cardRepository,
                        deckRepository: deckRepository
                    )
                } else {
                    CardDetailView(
                        card: resolved,
                        repository: cardRepository,
                        deckRepository: deckRepository,
                        onScanAnother: {}
                    )
                }
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await resolveCard(name: cardName) }
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .task { await resolveCard(name: cardName) }
        }
    }

    private func commonCardsGrid(_ cards: [CommonCardEntry]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(cards) { card in
                    gridCard(card)
                }
            }
        }
    }

    private func gridCard(_ entry: CommonCardEntry) -> some View {
        Button {
            Task { await openCardDetail(name: entry.cardName) }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if let card = resolvedCards[entry.cardName],
                       let urlString = card.imageURIs["small"] ?? card.imageURIs["normal"] ?? card.imageURIs["large"],
                       let url = URL(string: urlString) {
                        CachedPhaseImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                gridPlaceholder(entry.cardName)
                            }
                        }
                    } else {
                        gridPlaceholder(entry.cardName)
                            .task { await resolveCard(name: entry.cardName) }
                    }
                    Text("\(entry.deckCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(6)
                }
                .frame(width: 110)
            }
        }
        .buttonStyle(.plain)
    }

    private func gridPlaceholder(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(MD3Theme.surfaceVariant)
            .aspectRatio(63.0 / 88.0, contentMode: .fit)
            .frame(width: 110)
            .overlay(
                Text(name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            )
    }

    private func signatureCardsList(_ names: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                Button {
                    Task { await openCardDetail(name: name) }
                } label: {
                    HStack {
                        Text(name)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(MD3Theme.onSurface)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < names.count - 1 {
                    Divider()
                }
            }
        }
        .background(MD3Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Variants

    private var variantsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Variants")
            Text("All \(group.variants.count) MTGTop8 archetype\(group.variants.count == 1 ? "" : "s") that merge into \"\(group.displayName)\"")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            VStack(spacing: 0) {
                ForEach(Array(group.variants.enumerated()), id: \.element.id) { idx, variant in
                    NavigationLink {
                        ArchetypeDecksView(
                            archetype: variant.name,
                            format: variant.format.displayName,
                            source: .online(
                                archetypeID: variant.archetypeID,
                                formatCode: variant.format.code
                            ),
                            cardRepository: cardRepository,
                            deckRepository: deckRepository
                        )
                    } label: {
                        variantRow(variant)
                    }
                    .buttonStyle(.plain)
                    if idx < group.variants.count - 1 {
                        Divider()
                    }
                }
            }
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func variantRow(_ variant: IndexedArchetype) -> some View {
        HStack(spacing: 8) {
            Text(variant.format.displayName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(MD3Theme.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MD3Theme.primaryContainer)
                .clipShape(Capsule())
            Text(variant.name)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MD3Theme.onSurface)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(MD3Theme.onSurfaceVariant)
    }

    // MARK: - Aggregation

    private func aggregateCards(forceRefresh: Bool) async {
        isAggregating = true
        defer { isAggregating = false }
        let result = await aggregator.aggregate(
            cacheKey: group.canonicalName,
            variants: group.variants,
            forceRefresh: forceRefresh
        )
        if let result {
            aggregation = result
            aggregationError = nil
            // Don't bulk-resolve here. Each row's `.task` in
            // `cardRowDestination` resolves itself lazily as it
            // scrolls into view. A bulk resolveAll() fires N parallel
            // tasks that all hop to the @MainActor-isolated
            // DatabaseManager, freezing the UI for several seconds —
            // especially bad when one of the names triggers the
            // Levenshtein fuzzy fallback (50-150ms per miss).
        } else if aggregation == nil {
            aggregationError = "Couldn't aggregate cards from MTGTop8 yet. Pull down to refresh."
        }
    }

    // MARK: - Card resolution (for grid view + tap)

    private func resolveCard(name: String) async {
        guard resolvedCards[name] == nil else { return }
        // Goes through CardResolver so the user's Default Printing
        // setting (Settings → Deck Display) is honored everywhere
        // we render a card image from a bare name.
        let resolver = CardResolver(cardRepository: cardRepository)
        if let card = await resolver.resolve(name: name) {
            resolvedCards[name] = card
        }
    }

    @MainActor
    private func openCardDetail(name: String) async {
        // Resolve and push CardDetailView via the navigation stack.
        // We can't push from a closure here without a path binding,
        // so the simpler UX is to just resolve and rely on the user
        // tapping into the variants list for full deck context.
        await resolveCard(name: name)
    }
}
