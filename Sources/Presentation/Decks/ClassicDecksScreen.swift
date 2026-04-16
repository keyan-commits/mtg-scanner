import SwiftUI

/// Browse the curated `ClassicArchetypes` database. Tap a row to see the
/// full decklist with each card resolved to a real printing.
/// Supports text search, format filter, and a sort mode that orders
/// archetypes by how closely they match the user's collection.
struct ClassicDecksScreen: View {

    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol

    @State private var searchText: String = ""
    @State private var formatFilter: String? = nil
    @State private var sortMode: SortMode = .era
    @State private var ownedQuantities: [String: Int] = [:]
    @State private var matchScores: [String: Double] = [:] // archetype.id → 0..1
    @State private var didLoadCollection: Bool = false

    enum SortMode: String, CaseIterable, Identifiable {
        case era = "Era"
        case name = "Name"
        case bestMatch = "Best match"
        var id: String { rawValue }
    }

    /// All formats present in the database, sorted alphabetically.
    private var allFormats: [String] {
        Array(Set(ClassicArchetypes.all.map(\.format))).sorted()
    }

    /// Archetypes after applying search + format filter, in display order
    /// determined by `sortMode`.
    private var filteredAndSorted: [ClassicArchetype] {
        var result = ClassicArchetypes.all

        // Text filter
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.name.lowercased().contains(q)
                    || $0.era.lowercased().contains(q)
                    || $0.format.lowercased().contains(q)
                    || $0.description.lowercased().contains(q)
            }
        }

        // Format filter
        if let formatFilter {
            result = result.filter { $0.format == formatFilter }
        }

        // Sort
        switch sortMode {
        case .era:
            // Preserve declared era ordering by index in `all`
            let originalIndex: [String: Int] = Dictionary(uniqueKeysWithValues:
                ClassicArchetypes.all.enumerated().map { ($1.id, $0) })
            result.sort { (originalIndex[$0.id] ?? 0) < (originalIndex[$1.id] ?? 0) }
        case .name:
            result.sort { $0.name < $1.name }
        case .bestMatch:
            result.sort { (matchScores[$0.id] ?? 0) > (matchScores[$1.id] ?? 0) }
        }

        return result
    }

    /// Groups the filtered list by era. Only used when `sortMode == .era`.
    private var grouped: [(era: String, archetypes: [ClassicArchetype])] {
        var result: [(era: String, archetypes: [ClassicArchetype])] = []
        for archetype in filteredAndSorted {
            if let idx = result.firstIndex(where: { $0.era == archetype.era }) {
                result[idx].archetypes.append(archetype)
            } else {
                result.append((era: archetype.era, archetypes: [archetype]))
            }
        }
        return result
    }

    var body: some View {
        List {
            if sortMode == .era && searchText.isEmpty && formatFilter == nil {
                Section {
                    Text("\(ClassicArchetypes.all.count) hand-curated tournament decks spanning 30 years of Magic. Tap one to see its decklist with real card printings, or save it as your own deck.")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .listRowBackground(Color.clear)
                }
            }

            if sortMode == .era {
                ForEach(grouped, id: \.era) { group in
                    Section(group.era) {
                        ForEach(group.archetypes) { archetype in
                            navigationRow(archetype)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(filteredAndSorted) { archetype in
                        navigationRow(archetype)
                    }
                } header: {
                    headerForFlatList
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Classic Decks")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search by name, era, or format")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    ScreenHelpButton(title: "Classic Decks", sections: [
                        HelpSection(icon: "books.vertical", title: "What's in here",
                                    body: "Hand-curated tournament decks spanning 30 years of Magic — from 1995 Type II to modern Legacy. Each entry is a representative configuration of a famous archetype."),
                        HelpSection(icon: "magnifyingglass", title: "Search",
                                    body: "Pull down to reveal the search bar. Matches against deck name, era, format, or description text."),
                        HelpSection(icon: "line.3.horizontal.decrease.circle", title: "Filter & sort",
                                    body: "The filter button has Sort (Era / Name / Best match) and Format submenus. The icon fills in when a filter is active."),
                        HelpSection(icon: "star", title: "Best match sort",
                                    body: "Compares each archetype against the cards in your decks and ranks by overlap. Cards already in your collection bubble decks you're closest to completing to the top — green badge = ≥70% match."),
                        HelpSection(icon: "rectangle.stack", title: "Tap to view",
                                    body: "Opens the full decklist with each card resolved to a real printing. Tap any card row to drill into the standard card detail view."),
                        HelpSection(icon: "square.and.arrow.down", title: "Save as your deck",
                                    body: "The Save button on the detail screen creates a brand new deck with all cards pre-loaded. Edit or modify it freely after — it's not linked to the original archetype."),
                    ])
                    Menu {
                        Picker("Sort", selection: $sortMode) {
                            ForEach(SortMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: sortIcon(mode)).tag(mode)
                            }
                        }
                        Divider()
                        Section("Format") {
                            Button("All formats") { formatFilter = nil }
                            ForEach(allFormats, id: \.self) { format in
                                Button(format) { formatFilter = format }
                            }
                        }
                    } label: {
                        Image(systemName: filterIcon)
                    }
                }
            }
        }
        .task {
            if !didLoadCollection {
                await loadCollectionScores()
                didLoadCollection = true
            }
        }
    }

    private var filterIcon: String {
        (formatFilter != nil) ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle"
    }

    private func sortIcon(_ mode: SortMode) -> String {
        switch mode {
        case .era: return "calendar"
        case .name: return "textformat"
        case .bestMatch: return "star"
        }
    }

    @ViewBuilder
    private var headerForFlatList: some View {
        HStack {
            if let formatFilter {
                Text(formatFilter)
            } else {
                Text("All formats")
            }
            Spacer()
            Text("\(filteredAndSorted.count)")
                .font(.caption.weight(.semibold))
        }
    }

    @ViewBuilder
    private func navigationRow(_ archetype: ClassicArchetype) -> some View {
        NavigationLink {
            ClassicDeckDetailView(
                archetype: archetype,
                deckRepository: deckRepository,
                cardRepository: cardRepository
            )
        } label: {
            row(archetype)
        }
    }

    private func row(_ archetype: ClassicArchetype) -> some View {
        let matchPercent = Int(round((matchScores[archetype.id] ?? 0) * 100))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(archetype.name)
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
                if didLoadCollection && matchPercent > 0 {
                    Text("\(matchPercent)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(matchColor(matchPercent))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(matchColor(matchPercent).opacity(0.15))
                        .clipShape(Capsule())
                }
                Text("\(archetype.totalCards)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .monospacedDigit()
            }
            Text(archetype.format)
                .font(MD3Typography.labelSmall)
                .foregroundStyle(MD3Theme.onSecondaryContainer)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(MD3Theme.secondaryContainer)
                .clipShape(Capsule())
            Text(archetype.description)
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private func matchColor(_ percent: Int) -> Color {
        switch percent {
        case 70...:  return .green
        case 40..<70: return .orange
        default:     return .gray
        }
    }

    /// Loads the user's collection via `ownedQuantitiesByName()` and computes
    /// match scores against every archetype (sum-of-mins similarity).
    private func loadCollectionScores() async {
        let quantities = (try? deckRepository.ownedQuantitiesByName()) ?? [:]
        ownedQuantities = quantities

        // Build a lowercased lookup for case-insensitive matching
        var lowered: [String: Int] = [:]
        for (name, qty) in quantities {
            lowered[name.lowercased(), default: 0] += qty
        }

        var scores: [String: Double] = [:]
        for archetype in ClassicArchetypes.all {
            var matched = 0
            var total = 0
            for (cardName, qty) in archetype.mainboard {
                total += qty
                let userQty = lowered[cardName.lowercased(), default: 0]
                matched += min(userQty, qty)
            }
            scores[archetype.id] = total > 0 ? Double(matched) / Double(total) : 0
        }
        matchScores = scores
    }
}
