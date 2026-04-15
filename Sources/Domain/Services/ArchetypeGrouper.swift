import Foundation

// MARK: - Models

/// One canonicalized "umbrella" archetype produced by merging every
/// MTGTop8 variant whose name reduces to the same canonical form.
///
/// Example: `"Affinity (Robots)"`, `"UW Affinity"`, `"Mono-Blue
/// Affinity"`, and `"Affinity"` all reduce to the canonical name
/// `"affinity"` and form a single `ArchetypeGroup` with display name
/// `"Affinity"` and four variants.
///
/// Used by the new Browse Archetypes screen to surface every major
/// archetype that exists on MTGTop8, while still giving each one its
/// own detail page with the variants list and aggregated common cards.
struct ArchetypeGroup: Identifiable, Sendable {
    /// Canonical lowercase form. Stable across runs.
    let canonicalName: String
    /// Title-cased display form derived from the most-common variant
    /// name (after canonicalization).
    let displayName: String
    /// Every MTGTop8 archetype that reduces to this canonical name.
    let variants: [IndexedArchetype]
    /// Optional curated content (intro, strategy, signature cards)
    /// from `MajorArchetypes`. Nil for auto-generated groups that
    /// don't have a hand-written entry yet.
    let curated: MajorArchetype?

    var id: String { canonicalName }

    /// Distinct formats this archetype has appeared in.
    var formats: [MTGTop8Format] {
        var seen = Set<String>()
        var result: [MTGTop8Format] = []
        for variant in variants {
            if seen.insert(variant.format.code).inserted {
                result.append(variant.format)
            }
        }
        return result
    }

    /// Combined `matchTerms` for the live aggregator. Includes the
    /// canonical name plus any curated `matchTerms` so the aggregator
    /// catches related variants the canonicalization missed.
    var matchTerms: [String] {
        var terms: [String] = [canonicalName]
        if let curated {
            terms.append(contentsOf: curated.matchTerms)
        }
        return terms
    }
}

// MARK: - Service protocol

protocol ArchetypeGrouperProtocol: Sendable {
    /// Loads the entire MTGTop8 catalog (or its cache) and groups
    /// every archetype by canonical name. Returns groups sorted by
    /// variant count descending, then alphabetically.
    func loadAllGroups(forceRefresh: Bool) async throws -> [ArchetypeGroup]
}

// MARK: - Implementation

/// Produces `ArchetypeGroup` lists by canonicalizing MTGTop8
/// archetype names and merging variants that share the same root.
///
/// The canonicalization heuristic strips:
/// - Parenthesized suffixes: `"Affinity (Robots)"` → `"Affinity"`
/// - Color-pair / wedge / shard prefixes: `"UW Affinity"` → `"Affinity"`
/// - "Mono-Color" prefixes: `"Mono Red Burn"` → `"Burn"`
/// - Generic descriptors: `"Affinity Combo"` → `"Affinity"`
///
/// Then lowercases and trims. The grouping is conservative —
/// archetypes that share a substantive name fragment stay together,
/// but unrelated decks (e.g., "Death's Shadow" vs. "Death and Taxes")
/// don't accidentally merge.
struct ArchetypeGrouper: ArchetypeGrouperProtocol {

    private let archetypeIndex: MTGTop8ArchetypeIndexProtocol

    init(archetypeIndex: MTGTop8ArchetypeIndexProtocol = MTGTop8ArchetypeIndex()) {
        self.archetypeIndex = archetypeIndex
    }

    // MARK: - Public

    func loadAllGroups(forceRefresh: Bool = false) async throws -> [ArchetypeGroup] {
        let archetypes = try await archetypeIndex.archetypes(forceRefresh: forceRefresh)
        return Self.group(archetypes: archetypes)
    }

    // MARK: - Grouping

    /// Groups a flat list of archetypes by canonical name. Static so
    /// it's directly testable.
    ///
    /// Pipeline:
    /// 1. Reduce each archetype name to a `canonical` lowercase root.
    /// 2. Look up a curated `MajorArchetype` whose `matchTerms`
    ///    include this canonical (or whose id matches it). When found,
    ///    REPLACE the bucket key with the curated major's `id`. This
    ///    is what merges "Burn" + "Red Deck Wins" + "Sligh (RDW)" into
    ///    a single "burn" bucket — they don't share canonical roots
    ///    but they ARE all listed in `Burn.matchTerms`.
    /// 3. Bucket archetypes by the (possibly aliased) key.
    /// 4. Pick the most-common display name within each bucket as the
    ///    group's display label, OR the curated major's display name
    ///    when one exists (so "Burn" wins over "Red Deck Wins" as the
    ///    visible label).
    static func group(archetypes: [IndexedArchetype]) -> [ArchetypeGroup] {
        var buckets: [String: [IndexedArchetype]] = [:]
        var displayNames: [String: [String: Int]] = [:]
        var curatedByBucket: [String: MajorArchetype] = [:]

        for archetype in archetypes {
            let raw = canonicalName(from: archetype.name)
            // Skip noise: empty / single-letter / "other"
            guard raw.count >= 2 else { continue }

            // Curated alias: if a major archetype claims this canonical
            // name via its id or matchTerms, the major's id becomes the
            // bucket key so all variant names merge under one umbrella.
            let bucketKey: String
            if let major = MajorArchetypes.curatedFor(canonicalName: raw) {
                bucketKey = major.id
                curatedByBucket[bucketKey] = major
            } else {
                bucketKey = raw
            }

            buckets[bucketKey, default: []].append(archetype)

            let cleaned = displayCleanName(from: archetype.name)
            displayNames[bucketKey, default: [:]][cleaned, default: 0] += 1
        }

        let groups: [ArchetypeGroup] = buckets.map { key, variants in
            let curated = curatedByBucket[key]
            // Curated display name wins over the most-common variant name
            // (so a Burn group whose only variants are "Red Deck Wins"
            // still surfaces as "Burn" to the user).
            let displayName: String
            if let curated {
                displayName = curated.name
            } else {
                let nameCounts = displayNames[key] ?? [:]
                displayName = nameCounts.max(by: { $0.value < $1.value })?.key
                    ?? titleCase(key)
            }
            return ArchetypeGroup(
                canonicalName: key,
                displayName: displayName,
                variants: variants.sorted { $0.name < $1.name },
                curated: curated
            )
        }

        return groups.sorted { lhs, rhs in
            if lhs.variants.count != rhs.variants.count {
                return lhs.variants.count > rhs.variants.count
            }
            return lhs.displayName < rhs.displayName
        }
    }

    // MARK: - Canonicalization

    /// Color/wedge/shard prefixes that strip from the start of an
    /// archetype name. Order matters — longer phrases first so
    /// "Mono Red" matches before "Red".
    private static let colorPrefixes: [String] = [
        // Mono prefixes (with optional dash/space)
        "mono-white ", "mono-blue ", "mono-black ", "mono-red ", "mono-green ",
        "mono white ", "mono blue ", "mono black ", "mono red ", "mono green ",
        // 5-color
        "5-color ", "5c ", "5 color ", "five color ", "five-color ", "wubrg ",
        // Shards / wedges
        "bant ", "esper ", "grixis ", "jund ", "naya ",
        "abzan ", "jeskai ", "mardu ", "sultai ", "temur ",
        // Two-color guild prefixes
        "azorius ", "dimir ", "rakdos ", "gruul ", "selesnya ",
        "orzhov ", "izzet ", "golgari ", "boros ", "simic ",
        // Two-letter color codes (with trailing space)
        "uw ", "ub ", "ur ", "ug ", "wb ", "wr ", "wg ",
        "br ", "bg ", "rg ", "wu ", "bu ", "ru ", "gu ",
        "rb ", "bw ", "rw ", "gw ", "gb ", "gr ",
    ]

    /// Generic descriptor suffixes that strip from the end.
    private static let suffixesToStrip: [String] = [
        " combo", " aggro", " control", " midrange", " tempo",
        " ramp", " tribal", " prison", " toolbox",
    ]

    /// Reduces an archetype name to its canonical lowercase root.
    /// Pure function — no I/O. Static so tests can call it directly.
    static func canonicalName(from raw: String) -> String {
        var name = raw.lowercased()

        // 1. Strip parenthesized suffixes: "affinity (robots)" → "affinity"
        if let parenIdx = name.firstIndex(of: "(") {
            name = String(name[..<parenIdx]).trimmingCharacters(in: .whitespaces)
        }

        // 2. Strip leading color / wedge / shard prefixes (repeatedly,
        // in case multiple are stacked).
        var changed = true
        while changed {
            changed = false
            for prefix in colorPrefixes {
                if name.hasPrefix(prefix) {
                    name = String(name.dropFirst(prefix.count))
                    changed = true
                    break
                }
            }
        }

        // 3. Strip generic descriptor suffixes
        for suffix in suffixesToStrip {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }

        // 4. Final trim
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cleans a raw archetype name for display (preserves case but
    /// strips parenthesized suffixes so "Affinity (Robots)" shows as
    /// "Affinity" in the bucket header).
    static func displayCleanName(from raw: String) -> String {
        var name = raw
        if let parenIdx = name.firstIndex(of: "(") {
            name = String(name[..<parenIdx]).trimmingCharacters(in: .whitespaces)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleCase(_ s: String) -> String {
        s.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
