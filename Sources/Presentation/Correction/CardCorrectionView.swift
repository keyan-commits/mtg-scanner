import SwiftUI

// MARK: - Card Correction View

/// Allows the user to search for and select the correct card when
/// the identification pipeline returns the wrong result.
///
/// Flow:
/// 1. User types a card name in the search field.
/// 2. Results appear from the local database (95K cards, instant).
/// 3. User taps a card name to see all printings (sets + collector numbers).
/// 4. User taps the exact printing to apply the correction.
struct CardCorrectionView: View {

    let repository: CardRepositoryProtocol
    let currentCard: Card?  // The wrongly-identified card — used to pre-filter
    let onCorrection: (Card) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [Card] = []
    @State private var selectedCardName: String?
    @State private var printings: [Card] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var didAutoLoad = false
    @State private var setFilterText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                    .background(MD3Theme.outlineVariant)
                resultsList
            }
            .background(MD3Theme.background)
            .navigationTitle("Correct Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(MD3Theme.primary)
                }
            }
        }
        .task {
            // Auto-populate with current card's name and show its printings
            if !didAutoLoad, let card = currentCard {
                didAutoLoad = true
                searchText = card.name
                selectedCardName = card.name
                loadPrintings(for: card.name)
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            TextField("Search card name...", text: $searchText)
                .font(MD3Typography.bodyLarge)
                .foregroundStyle(MD3Theme.onSurface)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { _, newValue in
                    performSearch(query: newValue)
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                    selectedCardName = nil
                    printings = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MD3Theme.surface)
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
        if let selectedName = selectedCardName {
            printingsList(for: selectedName)
        } else if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
            noResultsView
        } else if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty {
            promptView
        } else {
            cardNamesList
        }
    }

    private var promptView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(MD3Theme.primary)
            Text("Type the correct card name above")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Type at least 3 characters to search")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Text("No cards found for \"\(searchText)\"")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("The card may not be in your local database. Try updating the Scryfall data from Settings, or check the spelling.")
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Scryfall online search link
            if let url = URL(string: "https://scryfall.com/search?q=\(searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                        Text("Search on Scryfall")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.primary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Card Names List (grouped by unique name)

    private var cardNamesList: some View {
        let uniqueNames = uniqueCardNames(from: searchResults)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(uniqueNames, id: \.self) { name in
                    Button {
                        selectedCardName = name
                        loadPrintings(for: name)
                    } label: {
                        HStack {
                            Text(name)
                                .font(MD3Typography.titleSmall)
                                .foregroundStyle(MD3Theme.onSurface)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Printings List

    private var filteredPrintings: [Card] {
        guard !setFilterText.isEmpty else { return printings }
        let query = setFilterText.lowercased()
        return printings.filter { card in
            card.set.name.lowercased().contains(query) ||
            card.set.code.lowercased().contains(query)
        }
    }

    private func printingsList(for cardName: String) -> some View {
        VStack(spacing: 0) {
            // Back button
            Button {
                selectedCardName = nil
                printings = []
                setFilterText = ""
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                    Text("Back to results")
                        .font(MD3Typography.labelMedium)
                }
                .foregroundStyle(MD3Theme.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 16)

            HStack {
                Text(cardName)
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
                Text("\(filteredPrintings.count) printings")
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Set filter field
            if printings.count > 10 {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .font(.caption)
                    TextField("Filter by set name or code...", text: $setFilterText)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurface)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !setFilterText.isEmpty {
                        Button {
                            setFilterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(MD3Theme.surfaceVariant.opacity(0.5))

                Divider()
                    .padding(.leading, 16)
            }

            if printings.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let displayed = filteredPrintings
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayed) { card in
                            Button {
                                onCorrection(card)
                                dismiss()
                            } label: {
                                printingRow(card: card)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private func printingRow(card: Card) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let urlString = card.imageURIs["small"],
               let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(MD3Theme.surfaceVariant)
                }
                .frame(width: 36, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.set.name)
                    .font(MD3Typography.titleSmall)
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(card.set.code.uppercased())
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(MD3Theme.primary)
                    Text("#\(card.collectorNumber)")
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }

            Spacer()

            if let usd = card.prices.usd {
                Text("$\(usd)")
                    .font(MD3Typography.labelMedium)
                    .foregroundStyle(MD3Theme.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Search Logic

    private func performSearch(query: String) {
        searchTask?.cancel()
        selectedCardName = nil
        printings = []

        guard query.count >= 3 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let results = try await repository.searchCards(query: query)
                guard !Task.isCancelled else { return }
                // Limit to 100 results to avoid UI lag
                let limited = Array(results.prefix(100))
                await MainActor.run {
                    searchResults = limited
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }

    private func loadPrintings(for name: String) {
        Task {
            do {
                var results = try await repository.findAllPrintings(name: name)

                // Sort by relevance: prioritize printings matching the current card's signals
                if let current = currentCard {
                    results.sort { a, b in
                        relevanceScore(a, for: current) > relevanceScore(b, for: current)
                    }
                }

                await MainActor.run {
                    printings = results
                }
            } catch {
                await MainActor.run {
                    printings = []
                }
            }
        }
    }

    /// Scores a printing's relevance to the current (wrongly identified) card's signals.
    /// Higher = more relevant. Matches artist and release year from the current card.
    private func relevanceScore(_ card: Card, for current: Card) -> Int {
        var score = 0

        // Artist match (strongest signal)
        if let a = card.artist, let ca = current.artist {
            let la = a.lowercased()
            let lca = ca.lowercased()
            if la == lca { score += 10 }
            else if la.contains(lca) || lca.contains(la) { score += 5 }
        }

        // Prefer expansion/core sets over promos
        switch card.set.setType {
        case "expansion": score += 3
        case "core": score += 2
        case "masters": score += 1
        default: break
        }

        // Penalize foreign/variant sets
        if card.set.name.lowercased().contains("foreign") { score -= 5 }

        return score
    }

    private func uniqueCardNames(from cards: [Card]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for card in cards {
            if seen.insert(card.name).inserted {
                names.append(card.name)
            }
        }
        return names
    }
}
