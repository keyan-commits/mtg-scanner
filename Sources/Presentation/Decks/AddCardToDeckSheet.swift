import SwiftUI

/// Sheet for searching the local card database and adding a card to a deck.
/// Used from DeckDetailView's "+" button.
struct AddCardToDeckSheet: View {

    let deck: DeckList
    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol
    let onAdded: () -> Void

    @State private var query: String = ""
    @State private var results: [Card] = []
    @State private var isSearching: Bool = false
    @State private var selectedCard: Card?
    @State private var quantity: Int = 4
    @State private var setFilterText: String = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredResults: [Card] {
        results.filter { $0.matchesSetFilter(setFilterText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                if let selectedCard {
                    quantitySection(for: selectedCard)
                } else if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty && query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                    Text("No cards found")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    Text("Type a card name to search")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if results.count > 1 {
                        SetFilterField(text: $setFilterText)
                    }
                    resultsList
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if selectedCard != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") { addAndDismiss() }
                    }
                }
            }
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2 else {
                    results = []
                    return
                }
                // Debounce
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
                await search(trimmed: trimmed)
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Card name", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .onChange(of: query) { _, _ in
                    selectedCard = nil
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    selectedCard = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Results List

    private var resultsList: some View {
        List(filteredResults) { card in
            Button {
                selectedCard = card
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("\(card.setNameWithYear) #\(card.collectorNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    // MARK: - Quantity Section

    private func quantitySection(for card: Card) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.headline)
                Text("\(card.setNameWithYear) #\(card.collectorNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)

            HStack {
                Text("Quantity")
                    .font(.body)
                Spacer()
                Stepper("\(quantity)", value: $quantity, in: 1...99)
                    .labelsHidden()
                Text("\(quantity)")
                    .font(.title3.monospacedDigit())
                    .frame(width: 32)
            }
            .padding(.horizontal, 16)

            Button {
                selectedCard = nil
            } label: {
                Text("Choose a different printing")
                    .font(.callout)
                    .foregroundStyle(.blue)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func search(trimmed: String) async {
        isSearching = true
        defer { isSearching = false }

        // Normalize smart quotes — iOS auto-converts ' to ' and that breaks DB lookups
        let normalized = trimmed
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")

        // Substring search returns cards whose name contains the query.
        let matches = (try? await cardRepository.searchCards(query: normalized)) ?? []

        // If all matches share a card name, show every printing.
        // Otherwise dedupe to one row per unique name.
        let uniqueNames = Set(matches.map { $0.name })
        let sorted = matches.sorted { ($0.releasedAt ?? "") > ($1.releasedAt ?? "") }

        if uniqueNames.count == 1 {
            // One card → show all printings
            if Task.isCancelled { return }
            results = sorted
            return
        }

        // Multiple cards → dedupe by name
        var seen: Set<String> = []
        var unique: [Card] = []
        for card in sorted {
            if !seen.contains(card.name) {
                seen.insert(card.name)
                unique.append(card)
                if unique.count >= 50 { break }
            }
        }
        if Task.isCancelled { return }
        results = unique
    }

    private func addAndDismiss() {
        guard let card = selectedCard else { return }
        _ = try? deckRepository.addItem(card: card, quantity: quantity, to: deck)
        onAdded()
        dismiss()
    }
}
