import Foundation

/// Resolves bare card names (e.g. from MTGTop8 decklists) into
/// concrete `Card` printings honoring the user's preferred
/// `PrintingStrategy`.
///
/// This is the single source of truth for "name → printing using the
/// user's display preference". Every screen that needs to render a
/// card image from just a name should go through here so the user's
/// Settings → Default Printing choice is respected app-wide.
///
/// Falls back through three lookup stages to handle the messy reality
/// of MTGTop8 transcriptions:
/// 1. Exact-match `findAllPrintings(name:)`
/// 2. Front-face match (`<query> // ...`) for DFCs / split / adventure
/// 3. Reverse front-face match when MTGTop8 lists the full DFC name
struct CardResolver: Sendable {

    let cardRepository: CardRepositoryProtocol

    init(cardRepository: CardRepositoryProtocol) {
        self.cardRepository = cardRepository
    }

    /// Resolves a card name to a printing matching `strategy` (or the
    /// user's default if nil). Returns nil if the name doesn't exist
    /// in the local Scryfall DB at all.
    ///
    /// `allowFuzzyFallback` controls whether the 4th lookup stage
    /// runs — Levenshtein over the entire 50K-card catalog, ~50-150ms
    /// per miss on the @MainActor-isolated DatabaseManager. Heavy
    /// scroll-driven contexts (e.g., the sought-after home list)
    /// pass `false` so they don't freeze the main actor on misses.
    func resolve(
        name: String,
        strategy: PrintingStrategy? = nil,
        allowFuzzyFallback: Bool = true
    ) async -> Card? {
        let printings = await lookupPrintings(forName: name, allowFuzzyFallback: allowFuzzyFallback)
        guard !printings.isEmpty else { return nil }
        let resolvedStrategy = await Self.resolveStrategy(strategy)
        return resolvedStrategy.pick(from: printings)
    }

    /// Resolves a batch of names in parallel. Names that fail to
    /// resolve are dropped from the result map.
    func resolveAll(
        names: [String],
        strategy: PrintingStrategy? = nil
    ) async -> [String: Card] {
        let resolvedStrategy = await Self.resolveStrategy(strategy)
        var result: [String: Card] = [:]
        await withTaskGroup(of: (String, Card?).self) { group in
            for name in names {
                group.addTask {
                    let card = await self.resolve(name: name, strategy: resolvedStrategy)
                    return (name, card)
                }
            }
            for await (name, card) in group {
                if let card { result[name] = card }
            }
        }
        return result
    }

    /// Reads the user's default strategy from the MainActor-isolated
    /// preference singleton when the caller didn't supply one. Hops
    /// to MainActor only when needed so per-call awaits are minimal.
    private static func resolveStrategy(_ explicit: PrintingStrategy?) async -> PrintingStrategy {
        if let explicit { return explicit }
        return await MainActor.run { PrintingStrategyPreference.shared.strategy }
    }

    /// All printings of `name` from the local DB, walking up to four
    /// fallback strategies. Identical to the inline lookup that lived
    /// in `MTGTop8DeckDetailView` — extracted here so every consumer
    /// gets the same behavior.
    private func lookupPrintings(forName name: String, allowFuzzyFallback: Bool = true) async -> [Card] {
        // 1. Exact match
        if let exact = try? await cardRepository.findAllPrintings(name: name),
           !exact.isEmpty {
            return exact
        }

        // 2. DFC/split/adventure forward fix: source listed only the
        // front face, local DB has the full "Front // Back" name.
        if let candidates = try? await cardRepository.searchCards(query: name) {
            let prefix = "\(name.lowercased()) // "
            let frontFaceMatches = candidates.filter { card in
                card.name.lowercased().hasPrefix(prefix)
            }
            if !frontFaceMatches.isEmpty {
                var seen = Set<String>()
                return frontFaceMatches.filter { card in
                    seen.insert(card.scryfallID).inserted
                }
            }
        }

        // 3. Reverse: source has "Front // Back" but local DB stores
        // only the front face by itself.
        if name.contains(" // ") {
            let frontFace = name.components(separatedBy: " // ").first ?? name
            if frontFace != name,
               let printings = try? await cardRepository.findAllPrintings(name: frontFace),
               !printings.isEmpty {
                return printings
            }
        }

        // 4. Typo-tolerant fuzzy match (opt-in). Catches cases like
        // "Loerien Revield" → "Lórien Revealed" where the source
        // (MTGTop8 transcription) has misspellings or dropped
        // diacritics. Skipped in scroll-heavy contexts because it
        // walks the entire 50K-card catalog on every miss.
        if allowFuzzyFallback,
           let fuzzy = try? await cardRepository.findFuzzyMatch(name: name),
           let printings = try? await cardRepository.findAllPrintings(name: fuzzy.name),
           !printings.isEmpty {
            return printings
        }

        return []
    }
}
