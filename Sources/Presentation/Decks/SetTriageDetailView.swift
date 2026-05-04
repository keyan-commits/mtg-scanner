import SwiftUI

/// Pull-list for one expansion. Loads every printing in the set, runs
/// each through `CardTriageService`, groups the results by tier, and
/// renders an ephemeral checklist — the user flips through their
/// physical pile, ticks what they find, leaves the rest in the box.
///
/// State is intentionally non-persistent. Checked entries clear when
/// the screen unmounts; the user isn't tracking a real collection,
/// they're working through one bulk pile in a sitting.
struct SetTriageDetailView: View {

    let setInfo: SetInfo
    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var allCards: [Card] = []
    @State private var ratings: [String: TriageRating] = [:]   // scryfallID → rating
    @State private var checked: Set<String> = []                 // scryfallID
    @State private var isLoading = true
    @State private var showLowValue = false
    @State private var hideChecked = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading cards…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allCards.isEmpty {
                ContentUnavailableView(
                    "No Cards",
                    systemImage: "tray",
                    description: Text("This set has no card records in the local database.")
                )
            } else {
                listBody
            }
        }
        .navigationTitle(setInfo.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCards() }
    }

    // MARK: - Derived

    /// Tiers shown in the order S → A → B → C, filtered by the
    /// "Show low-value" toggle.
    private var visibleTiers: [TriageRating.Tier] {
        showLowValue ? [.s, .a, .b, .c] : [.s, .a]
    }

    /// scryfallID lists per tier, sorted by unit price desc.
    private var cardsByTier: [TriageRating.Tier: [Card]] {
        var out: [TriageRating.Tier: [Card]] = [:]
        for card in allCards {
            guard let rating = ratings[card.scryfallID] else { continue }
            out[rating.tier, default: []].append(card)
        }
        for tier in out.keys {
            out[tier]?.sort { lhs, rhs in
                let lp = ratings[lhs.scryfallID]?.unitPriceUSD ?? 0
                let rp = ratings[rhs.scryfallID]?.unitPriceUSD ?? 0
                return lp > rp
            }
        }
        return out
    }

    /// Flat list of cards currently visible — used as the source for
    /// the swipe pager when the user taps a row.
    private var visibleCards: [Card] {
        let buckets = cardsByTier
        return visibleTiers.flatMap { tier in
            (buckets[tier] ?? []).filter { !hideChecked || !checked.contains($0.scryfallID) }
        }
    }

    // MARK: - Body

    private var listBody: some View {
        List {
            Section {
                summaryRow
                    .listRowBackground(Color.clear)
                togglesRow
                    .listRowBackground(Color.clear)
            }

            ForEach(visibleTiers, id: \.self) { tier in
                let cards = (cardsByTier[tier] ?? [])
                    .filter { !hideChecked || !checked.contains($0.scryfallID) }
                if !cards.isEmpty {
                    Section(header: tierHeader(tier, count: cards.count)) {
                        ForEach(cards, id: \.id) { card in
                            row(for: card)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var summaryRow: some View {
        let buckets = cardsByTier
        let s = (buckets[.s] ?? []).count
        let a = (buckets[.a] ?? []).count
        let b = (buckets[.b] ?? []).count
        let c = (buckets[.c] ?? []).count
        return HStack(spacing: 8) {
            tierPill("S", s, color: .red)
            tierPill("A", a, color: .orange)
            tierPill("B", b, color: .gray)
            tierPill("C", c, color: MD3Theme.onSurfaceVariant.opacity(0.5))
            Spacer()
            Text("\(allCards.count) cards")
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    private var togglesRow: some View {
        HStack(spacing: 16) {
            Toggle("Show low-value", isOn: $showLowValue)
                .toggleStyle(.switch)
                .font(.caption)
            Toggle("Hide checked", isOn: $hideChecked)
                .toggleStyle(.switch)
                .font(.caption)
        }
    }

    private func tierPill(_ label: String, _ count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color)
                .clipShape(Capsule())
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MD3Theme.onSurface)
        }
    }

    private func tierHeader(_ tier: TriageRating.Tier, count: Int) -> some View {
        HStack {
            Text(tierTitle(tier))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tierColor(tier))
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    private func tierTitle(_ tier: TriageRating.Tier) -> String {
        switch tier {
        case .s: return "TIER S — SELL TOP DOLLAR"
        case .a: return "TIER A — WORTH LISTING"
        case .b: return "TIER B — LOW-VALUE SINGLES"
        case .c: return "TIER C — BULK"
        }
    }

    private func tierColor(_ tier: TriageRating.Tier) -> Color {
        switch tier {
        case .s: return .red
        case .a: return .orange
        case .b: return .gray
        case .c: return MD3Theme.onSurfaceVariant
        }
    }

    // MARK: - Row

    private func row(for card: Card) -> some View {
        let rating = ratings[card.scryfallID]
        let isChecked = checked.contains(card.scryfallID)
        return HStack(spacing: 10) {
            Button {
                if isChecked {
                    checked.remove(card.scryfallID)
                } else {
                    checked.insert(card.scryfallID)
                }
            } label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isChecked ? MD3Theme.primary : MD3Theme.onSurfaceVariant.opacity(0.7))
            }
            .buttonStyle(.plain)

            NavigationLink {
                if let index = visibleCards.firstIndex(where: { $0.id == card.id }) {
                    CardListPagerView(
                        cards: visibleCards,
                        initialIndex: index,
                        cardRepository: cardRepository,
                        deckRepository: deckRepository
                    )
                }
            } label: {
                rowContent(card: card, rating: rating, isChecked: isChecked)
            }
            .buttonStyle(.plain)
        }
    }

    private func rowContent(card: Card, rating: TriageRating?, isChecked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(card.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isChecked ? MD3Theme.onSurfaceVariant : MD3Theme.onSurface)
                    .strikethrough(isChecked)
                    .lineLimit(1)
                Text("#\(card.collectorNumber)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Text(rarityLetter(card.rarity))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(rarityColor(card.rarity))
                Spacer()
                if let usd = rating?.unitPriceUSD {
                    Text(String(format: "$%.2f", usd))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(MD3Theme.primary)
                }
            }
            if let rating, !badges(for: rating).isEmpty {
                badgeRow(badges(for: rating))
            }
        }
        .padding(.vertical, 4)
        .opacity(isChecked ? 0.55 : 1.0)
    }

    private func rarityLetter(_ rarity: CardRarity) -> String {
        switch rarity {
        case .common: return "C"
        case .uncommon: return "U"
        case .rare: return "R"
        case .mythic: return "M"
        }
    }

    private func rarityColor(_ rarity: CardRarity) -> Color {
        switch rarity {
        case .mythic: return .orange
        case .rare: return .yellow.opacity(0.85)
        case .uncommon: return .gray
        case .common: return MD3Theme.onSurfaceVariant
        }
    }

    // MARK: - Badges

    private struct Badge: Identifiable {
        let id = UUID()
        let text: String
        let color: Color
    }

    private func badges(for rating: TriageRating) -> [Badge] {
        var out: [Badge] = []
        if rating.isReservedList {
            out.append(Badge(text: "Reserved", color: .yellow))
        }
        if !rating.staplesFormats.isEmpty {
            let label = rating.staplesFormats
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: "/")
            out.append(Badge(text: "Staple: \(label)", color: .purple))
        }
        for list in rating.lists {
            out.append(Badge(text: list, color: .green))
        }
        return out
    }

    private func badgeRow(_ badges: [Badge]) -> some View {
        HStack(spacing: 4) {
            ForEach(badges) { b in
                Text(b.text)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(b.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(b.color.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Loading

    /// Process-wide cache. Triage is deterministic given the local DB
    /// + the curated lists, so re-running on the same set is wasted
    /// work.
    nonisolated(unsafe) private static var cache: [String: (cards: [Card], ratings: [String: TriageRating])] = [:]

    private func loadCards() async {
        if let cached = Self.cache[setInfo.code] {
            allCards = cached.cards
            ratings = cached.ratings
            isLoading = false
            return
        }

        let cards = (try? await cardRepository.fetchCardsBySet(setCode: setInfo.code)) ?? []
        var ratingMap: [String: TriageRating] = [:]
        for card in cards {
            ratingMap[card.scryfallID] = CardTriageService.rate(card)
        }

        Self.cache[setInfo.code] = (cards, ratingMap)
        allCards = cards
        ratings = ratingMap
        isLoading = false
    }
}
