import SwiftUI

/// Set picker for the Triage feature. Lets the user pick an expansion
/// and see a pull-list of every card in that set worth taking out of a
/// bulk box (Tier S + A by default), so they can flip through a
/// physical pile and separate the keepers from the leave-in-the-box
/// crap without scanning anything.
///
/// Modeled on `TopCardsScreen` — a focused fork rather than a shared
/// abstraction so the destination view, header copy, and (eventually)
/// any sort criteria specific to triage can evolve independently.
struct SetTriageScreen: View {

    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var allSets: [SetInfo] = []
    @State private var searchText: String = ""
    @State private var selectedGroup: SetGroup = .expansion
    @State private var isLoading = true

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
                Picker("", selection: $selectedGroup) {
                    ForEach(SetGroup.allCases) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    Section {
                        Text("Pick an expansion to see every card worth pulling out of a bulk pile — sorted by sell-worthiness, with the bulk hidden by default.")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(filteredSets, id: \.code) { setInfo in
                            NavigationLink {
                                SetTriageDetailView(
                                    setInfo: setInfo,
                                    cardRepository: cardRepository,
                                    deckRepository: deckRepository
                                )
                            } label: {
                                setRow(setInfo)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Set Triage")
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
        allSets = sets.sorted { a, b in
            (a.releasedAt ?? "0000") > (b.releasedAt ?? "0000")
        }
        isLoading = false
    }
}
