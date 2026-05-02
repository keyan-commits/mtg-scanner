import SwiftUI

/// Browse every major archetype MTGTop8 has indexed, with related
/// variants merged into umbrella groups (e.g. "Affinity (Robots)" +
/// "UW Affinity" + "Mono-Blue Affinity" → one "Affinity" entry).
///
/// Each tap opens `MajorArchetypeDetailView` with:
/// - The hand-curated intro and "how to play" (when one of the
///   ~12 iconic majors); generic placeholder otherwise
/// - The full list of variants the group merged from
/// - Live-aggregated common cards across all variants' latest #1
///   decks (cached 7 days)
///
/// For the per-format browser (un-merged, with each row showing the
/// latest #1 for ONE archetype), see `FormatsScreen`.
struct BrowseArchetypesScreen: View {

    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    private let grouper: ArchetypeGrouperProtocol
    private let aggregator: CommonCardsAggregatorProtocol

    @State private var groups: [ArchetypeGroup] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String?
    @State private var searchText: String = ""

    init(
        cardRepository: CardRepositoryProtocol,
        deckRepository: DeckListRepository,
        grouper: ArchetypeGrouperProtocol = ArchetypeGrouper(),
        aggregator: CommonCardsAggregatorProtocol = CommonCardsAggregator()
    ) {
        self.cardRepository = cardRepository
        self.deckRepository = deckRepository
        self.grouper = grouper
        self.aggregator = aggregator
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading && groups.isEmpty {
                loadingState
            } else if let loadError, groups.isEmpty {
                errorState(loadError)
            } else {
                content
            }
        }
        .navigationTitle("Browse Archetypes")
        .navigationBarTitleDisplayMode(.inline)
        .background(MD3Theme.background)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search archetypes")
        .onChange(of: searchText) { _, newValue in
            // Debounce: update filtered list after 200ms
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if searchText == newValue {
                    debouncedSearch = newValue
                }
            }
        }
        .task {
            await load()
        }
        .mtgTop8OutageBanner()
    }

    // MARK: - Loading / error

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading archetypes from MTGTop8…")
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(MD3Theme.error)
            Text(message)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") {
                Task { await load(forceRefresh: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    @State private var debouncedSearch: String = ""

    private var filteredGroups: [ArchetypeGroup] {
        let trimmed = debouncedSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return groups }
        return groups.filter { group in
            if group.canonicalName.contains(trimmed) { return true }
            if group.displayName.lowercased().contains(trimmed) { return true }
            return group.variants.contains { $0.name.lowercased().contains(trimmed) }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                summaryHeader
                ForEach(Array(filteredGroups.enumerated()), id: \.element.id) { idx, group in
                    NavigationLink {
                        MajorArchetypeDetailView(
                            group: group,
                            cardRepository: cardRepository,
                            deckRepository: deckRepository,
                            aggregator: aggregator
                        )
                    } label: {
                        groupRow(group)
                    }
                    .buttonStyle(.plain)
                    if idx < filteredGroups.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
                if filteredGroups.isEmpty {
                    Text("No archetypes match \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .padding(40)
                }
            }
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(16)
        }
        .refreshable {
            await load(forceRefresh: true)
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(groups.count) archetypes")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MD3Theme.primary)
                .textCase(.uppercase)
            Text("Variants merged by name across every format MTGTop8 tracks")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func groupRow(_ group: ArchetypeGroup) -> some View {
        HStack(spacing: 12) {
            iconView(for: group)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)
                    if group.curated != nil {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(subtitle(for: group))
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.5))
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconView(for group: ArchetypeGroup) -> some View {
        let iconName = group.curated?.iconName ?? "rectangle.stack.fill"
        let tint = group.curated.flatMap { Color(hex: $0.tintHex) } ?? MD3Theme.primary
        RoundedRectangle(cornerRadius: 8)
            .fill(tint.opacity(0.18))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }

    private func subtitle(for group: ArchetypeGroup) -> String {
        let variantWord = group.variants.count == 1 ? "variant" : "variants"
        let formatCount = group.formats.count
        let formatWord = formatCount == 1 ? "format" : "formats"
        return "\(group.variants.count) \(variantWord) · \(formatCount) \(formatWord)"
    }

    // MARK: - Loading

    private func load(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await grouper.loadAllGroups(forceRefresh: forceRefresh)
            loadError = nil
        } catch {
            loadError = "Could not load archetype catalog from MTGTop8."
        }
    }
}

// MARK: - Color hex helper

extension Color {
    /// Initializes a `Color` from a hex string (e.g. "#E74C3C").
    /// Returns gray on parse failure.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let value = UInt64(s, radix: 16) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
