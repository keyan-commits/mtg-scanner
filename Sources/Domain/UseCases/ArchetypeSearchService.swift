import Foundation

// MARK: - Result

/// How a matched archetype's decks should be looked up. Hidden from the
/// UI — `ArchetypeDecksView` switches on it to call the right MTGTop8
/// endpoint.
enum ArchetypeSource: Sendable, Equatable {
    /// Hand-curated archetype from `ClassicArchetypes`. We have no
    /// MTGTop8 archetype ID, so the deck lookup falls back to seeding
    /// MTGTop8's card-name search with our `signatureCard`.
    case classic(signatureCard: String)
    /// Live archetype from MTGTop8's format index. The MTGTop8 archetype
    /// ID lets us hit `/archetype?a=<id>&f=<format>` directly — no
    /// signature-card workaround needed.
    case online(archetypeID: String, formatCode: String)
}

/// A single hit from `ArchetypeSearchService.search`. Wraps the source
/// metadata in a UI-friendly form.
struct ArchetypeSearchResult: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    /// Human-readable format label (e.g. "Modern", "Type II").
    let format: String
    /// Era / context label shown in the UI (e.g. "1996", "Live").
    let era: String
    let source: ArchetypeSource
}

// MARK: - Service

/// Searches for deck archetypes by name across two sources:
///
/// 1. **`ClassicArchetypes`** — a hand-curated catalog of historical
///    decks (Necropotence Black, Caw-Blade, etc.). Offline, instant.
/// 2. **`MTGTop8ArchetypeIndex`** — live archetype names scraped from
///    MTGTop8's per-format index pages, cached for 7 days. Covers
///    every current archetype MTGTop8 has indexed (Burn, Boros Energy,
///    Domain Zoo, etc.).
///
/// Online results are preferred when both sources have a match for the
/// same name (the live index has accurate deck counts and lets us hit
/// MTGTop8's native archetype detail page).
struct ArchetypeSearchService: Sendable {

    /// Maximum number of results returned per query.
    static let resultLimit = 25

    /// Cards excluded from signature-card selection because they don't
    /// narrow down an MTGTop8 search.
    private static let basicLands: Set<String> = [
        "Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes",
        "Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp",
        "Snow-Covered Mountain", "Snow-Covered Forest",
    ]

    private let classicArchetypes: [ClassicArchetype]
    private let onlineIndex: MTGTop8ArchetypeIndexProtocol?
    /// Formats to query online. Default covers everything that's
    /// commonly tournament-tracked.
    private let onlineFormats: [MTGTop8Format]

    init(
        classicArchetypes: [ClassicArchetype] = ClassicArchetypes.all,
        onlineIndex: MTGTop8ArchetypeIndexProtocol? = MTGTop8ArchetypeIndex(),
        onlineFormats: [MTGTop8Format] = MTGTop8Format.allCases
    ) {
        self.classicArchetypes = classicArchetypes
        self.onlineIndex = onlineIndex
        self.onlineFormats = onlineFormats
    }

    // MARK: - Public API

    /// Searches both the offline classic catalog and the online MTGTop8
    /// index. Online results take priority when names collide.
    func search(_ query: String) async -> [ArchetypeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        // Run classic + online searches in parallel.
        async let classicTask = searchClassic(trimmed)
        async let onlineTask = searchOnline(trimmed)
        let classicHits = await classicTask
        let onlineHits = await onlineTask

        // Online wins on name collisions — its data is fresher and we
        // have a real archetype ID to use for deck lookup.
        let onlineNames = Set(onlineHits.map { $0.name.lowercased() })
        let merged = onlineHits + classicHits.filter {
            !onlineNames.contains($0.name.lowercased())
        }
        return Array(merged.prefix(Self.resultLimit))
    }

    /// Forces a refresh of the online catalog (used by pull-to-refresh
    /// in the UI). Best-effort: errors are swallowed silently so a
    /// network blip doesn't break the search.
    func refreshOnlineIndex() async {
        guard let onlineIndex else { return }
        _ = try? await onlineIndex.archetypes(forceRefresh: true)
    }

    // MARK: - Classic source

    private func searchClassic(_ query: String) -> [ArchetypeSearchResult] {
        let lowered = query.lowercased()
        var exact: [ClassicArchetype] = []
        var prefix: [ClassicArchetype] = []
        var substring: [ClassicArchetype] = []

        for archetype in classicArchetypes {
            let lowerName = archetype.name.lowercased()
            if lowerName == lowered {
                exact.append(archetype)
            } else if lowerName.hasPrefix(lowered) {
                prefix.append(archetype)
            } else if lowerName.contains(lowered) {
                substring.append(archetype)
            }
        }

        let byName: (ClassicArchetype, ClassicArchetype) -> Bool = { $0.name < $1.name }
        let ranked = exact.sorted(by: byName)
            + prefix.sorted(by: byName)
            + substring.sorted(by: byName)

        return ranked.compactMap { archetype in
            guard let signature = Self.signatureCard(for: archetype) else { return nil }
            return ArchetypeSearchResult(
                id: "classic-\(archetype.id)",
                name: archetype.name,
                format: archetype.format,
                era: archetype.era,
                source: .classic(signatureCard: signature)
            )
        }
    }

    // MARK: - Online source

    private func searchOnline(_ query: String) async -> [ArchetypeSearchResult] {
        guard let onlineIndex else { return [] }
        guard let hits = try? await onlineIndex.search(
            query,
            in: onlineFormats,
            limit: Self.resultLimit
        ) else { return [] }

        return hits.map { hit in
            ArchetypeSearchResult(
                id: hit.id,
                name: hit.name,
                format: hit.format.displayName,
                era: "Live",
                source: .online(
                    archetypeID: hit.archetypeID,
                    formatCode: hit.format.code
                )
            )
        }
    }

    // MARK: - Signature card

    /// Picks the most-played non-basic-non-land card from the archetype's
    /// mainboard. Returns nil if every entry is a basic land (shouldn't
    /// happen for any real archetype, but the type system asks).
    static func signatureCard(for archetype: ClassicArchetype) -> String? {
        archetype.mainboard
            .filter { !basicLands.contains($0.key) }
            .max { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                // Deterministic tiebreak: alphabetically later name wins
                // (so two calls always return the same signature card).
                return lhs.key < rhs.key
            }?
            .key
    }
}
