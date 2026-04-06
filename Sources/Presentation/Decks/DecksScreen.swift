import SwiftUI

/// Lists all user-owned decks. Tap a deck to see its purchase checklist.
struct DecksScreen: View {

    let repository: DeckListRepository

    @State private var decks: [DeckList] = []
    @State private var showCreateSheet = false
    @State private var newDeckName = ""
    @State private var newDeckFormat = ""

    var body: some View {
        Group {
            if decks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(decks) { deck in
                        NavigationLink(destination: DeckDetailView(deck: deck, repository: repository)) {
                            deckRow(deck)
                        }
                    }
                    .onDelete(perform: deleteDecks)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("My Decks")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createDeckSheet
        }
        .onAppear { reload() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("No decks yet")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Create a deck to start tracking the cards you need to buy.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            MD3FilledButton("Create Deck") {
                showCreateSheet = true
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Deck Row

    private func deckRow(_ deck: DeckList) -> some View {
        let total = deck.items.count
        let needed = deck.items.filter { $0.status == .needed }.count
        let ordered = deck.items.filter { $0.status == .ordered }.count
        let arrived = deck.items.filter { $0.status == .arrived }.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(deck.name)
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
                if let format = deck.format, !format.isEmpty {
                    Text(format)
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(MD3Theme.onSecondaryContainer)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(MD3Theme.secondaryContainer)
                        .clipShape(Capsule())
                }
            }
            if total > 0 {
                HStack(spacing: 12) {
                    statusBadge("Needed", count: needed, color: MD3Theme.error)
                    statusBadge("Ordered", count: ordered, color: .orange)
                    statusBadge("Arrived", count: arrived, color: .green)
                }
            } else {
                Text("Empty")
                    .font(MD3Typography.bodySmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(MD3Typography.labelSmall)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    // MARK: - Create Deck Sheet

    private var createDeckSheet: some View {
        NavigationStack {
            Form {
                Section("Deck Info") {
                    TextField("Deck Name", text: $newDeckName)
                    TextField("Format (optional)", text: $newDeckFormat)
                }
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showCreateSheet = false
                        newDeckName = ""
                        newDeckFormat = ""
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        createDeck()
                    }
                    .disabled(newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        decks = (try? repository.fetchAllDecks()) ?? []
    }

    private func createDeck() {
        let trimmedName = newDeckName.trimmingCharacters(in: .whitespaces)
        let trimmedFormat = newDeckFormat.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        try? repository.createDeck(name: trimmedName, format: trimmedFormat.isEmpty ? nil : trimmedFormat)
        newDeckName = ""
        newDeckFormat = ""
        showCreateSheet = false
        reload()
    }

    private func deleteDecks(at offsets: IndexSet) {
        for index in offsets {
            try? repository.deleteDeck(decks[index])
        }
        reload()
    }
}
