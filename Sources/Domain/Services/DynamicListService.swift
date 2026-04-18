import Foundation

/// Builds curated card lists dynamically from the local database instead of
/// hardcoding card names. Lists auto-update when the database refreshes.
@MainActor
final class DynamicListService {

    static let shared = DynamicListService()

    private var cachedReservedList: [LandCategory]?
    private var cachedSecretLairDrops: [LandCategory]?
    private var databaseManager: DatabaseManager?

    func configure(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    /// Clears cached lists so they're rebuilt on next access.
    func invalidateCache() {
        cachedReservedList = nil
        cachedSecretLairDrops = nil
    }

    // MARK: - Reserved List

    /// Returns Reserved List categories built from the database.
    /// Groups cards by supertype: Lands, Artifacts, Enchantments, Creatures, Spells.
    func reservedList() async -> [LandCategory] {
        if let cached = cachedReservedList { return cached }
        guard let db = databaseManager else { return [] }

        do {
            let records = try await db.fetchReservedCards()
            guard !records.isEmpty else { return [] }

            var lands: [String] = []
            var artifacts: [String] = []
            var enchantments: [String] = []
            var creatures: [String] = []
            var spells: [String] = []    // instants + sorceries
            var seen = Set<String>()     // deduplicate by name

            for record in records {
                let name = record.name
                guard !seen.contains(name) else { continue }
                seen.insert(name)

                let type = record.typeLine.lowercased()
                if type.contains("land") {
                    lands.append(name)
                } else if type.contains("instant") || type.contains("sorcery") {
                    spells.append(name)
                } else if type.contains("enchantment") {
                    enchantments.append(name)
                } else if type.contains("creature") || type.contains("artifact creature") {
                    creatures.append(name)
                } else if type.contains("artifact") {
                    artifacts.append(name)
                } else {
                    // Catch-all: put in spells
                    spells.append(name)
                }
            }

            let categories: [LandCategory] = [
                LandCategory(
                    id: "rl-lands",
                    name: "Reserved List Lands (\(lands.count))",
                    iconName: "map.fill",
                    description: "All \(lands.count) lands on the Reserved List. Includes the 10 original dual lands, the Urza's Saga 'Cradle cycle,' and other unique early-era lands that will never be reprinted.",
                    cardNames: lands.sorted()
                ),
                LandCategory(
                    id: "rl-artifacts",
                    name: "Reserved List Artifacts (\(artifacts.count))",
                    iconName: "gearshape.fill",
                    description: "All \(artifacts.count) artifacts on the Reserved List. Includes Black Lotus, the five Moxen, Time Vault, Lion's Eye Diamond, Mox Diamond, and more.",
                    cardNames: artifacts.sorted()
                ),
                LandCategory(
                    id: "rl-enchantments",
                    name: "Reserved List Enchantments (\(enchantments.count))",
                    iconName: "sparkles",
                    description: "All \(enchantments.count) enchantments on the Reserved List. Includes Moat, The Abyss, Chains of Mephistopheles, Survival of the Fittest, and more.",
                    cardNames: enchantments.sorted()
                ),
                LandCategory(
                    id: "rl-creatures",
                    name: "Reserved List Creatures (\(creatures.count))",
                    iconName: "figure.stand",
                    description: "All \(creatures.count) creatures on the Reserved List (including artifact creatures). From Juzam Djinn to Sliver Queen.",
                    cardNames: creatures.sorted()
                ),
                LandCategory(
                    id: "rl-spells",
                    name: "Reserved List Spells (\(spells.count))",
                    iconName: "wand.and.stars",
                    description: "All \(spells.count) instants and sorceries on the Reserved List. Includes Ancestral Recall, Time Walk, Yawgmoth's Will, and more.",
                    cardNames: spells.sorted()
                ),
            ]

            cachedReservedList = categories
            return categories
        } catch {
            print("[DynamicListService] Failed to fetch reserved cards: \(error)")
            return []
        }
    }

    // MARK: - Secret Lair Lands

    /// Known collector-number ranges mapped to drop names. Used to give
    /// auto-discovered groups friendly display names.
    private static let knownDropsByRange: [(range: ClosedRange<Int>, name: String, icon: String)] = [
        (1...5, "Eldraine Wonderland", "wand.and.stars"),
        (63...67, "The Godzilla Lands", "flame.fill"),
        (100...109, "Happy Little Gathering (Bob Ross)", "paintpalette.fill"),
        (239...243, "Unfathomable Crushing Brutality", "bolt.fill"),
        (254...258, "The Full-Text Lands", "text.justify.left"),
        (325...329, "PixelSnowLands.jpg", "snowflake"),
        (359...363, "The Dracula Lands", "moon.fill"),
        (384...395, "The Astrology Lands", "star.circle.fill"),
        (415...419, "Shades Not Included", "sun.max.fill"),
        (448...452, "Secret Lair x Fortnite", "gamecontroller.fill"),
        (484...488, "Secret Lair x Arcane", "sparkle"),
        (1088...1092, "Transformers Lands", "gearshape.fill"),
        (1130...1134, "Special Guest: Kozyndan", "paintbrush.pointed.fill"),
        (1190...1194, "Post Malone: The Lands", "music.note"),
        (1382...1386, "Featuring: Gary Baseman", "theatermasks.fill"),
        (1399...1403, "Featuring: JungShan", "mountain.2.fill"),
        (1468...1472, "PixelLands_v02.jpg", "square.grid.3x3.fill"),
        (1473...1477, "PixelSnowLands v2 (ELK64)", "snowflake.circle.fill"),
        (1478...1482, "The Strange Sands", "leaf.fill"),
        (1513...1515, "Artist Series: Alayna Danner", "paintbrush.fill"),
        (1647...1656, "Secret Lair x Brain Dead", "brain.fill"),
        (1939...1943, "Secret Lair x SpongeBob", "water.waves"),
        (1945...1949, "Flower Power", "camera.macro"),
        (1950...1954, "Secret Lair x Spider-Man", "web.camera.fill"),
        (2076...2080, "KEXP: Where the Music Matters", "radio.fill"),
        (2144...2147, "Special Guest: Kelogsloops", "drop.fill"),
        (2509...2513, "D&D: Forgotten Realms Lands", "shield.fill"),
    ]

    /// Returns Secret Lair basic land drops built from the database.
    /// Groups by collector number proximity to correctly merge multi-artist drops.
    func secretLairDrops() async -> [LandCategory] {
        if let cached = cachedSecretLairDrops { return cached }
        guard let db = databaseManager else { return [] }

        do {
            let records = try await db.fetchSecretLairBasics()
            guard !records.isEmpty else { return [] }

            // Sort by collector number (numeric)
            let sorted = records.sorted {
                (Int($0.collectorNumber.filter(\.isNumber)) ?? 0) < (Int($1.collectorNumber.filter(\.isNumber)) ?? 0)
            }

            // Group by collector number proximity (gap > 10 = new group)
            var groups: [[CardRecord]] = []
            var currentGroup: [CardRecord] = []

            for record in sorted {
                let num = Int(record.collectorNumber.filter(\.isNumber)) ?? 0
                if let lastNum = currentGroup.last.flatMap({ Int($0.collectorNumber.filter(\.isNumber)) }),
                   num - lastNum > 10 {
                    if !currentGroup.isEmpty { groups.append(currentGroup) }
                    currentGroup = [record]
                } else {
                    currentGroup.append(record)
                }
            }
            if !currentGroup.isEmpty { groups.append(currentGroup) }

            // Build categories from groups
            var categories: [LandCategory] = []

            for group in groups {
                let firstNum = Int(group.first?.collectorNumber.filter(\.isNumber) ?? "0") ?? 0
                let artists = Array(Set(group.compactMap(\.artist))).sorted()
                let artistLabel = artists.isEmpty ? "Unknown" : artists.joined(separator: ", ")

                // Look up known drop name by collector number range
                let known = Self.knownDropsByRange.first { $0.range.contains(firstNum) }
                let dropName = known?.name ?? artistLabel
                let icon = known?.icon ?? "paintbrush.fill"

                let isSnow = group.first?.name.contains("Snow") ?? false
                let cardNames: [String]
                if isSnow {
                    cardNames = ["Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp", "Snow-Covered Mountain", "Snow-Covered Forest"]
                } else {
                    let basicOrder = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"]
                    cardNames = Array(Set(group.map(\.name))).sorted {
                        (basicOrder.firstIndex(of: $0) ?? 99) < (basicOrder.firstIndex(of: $1) ?? 99)
                    }
                }

                let collectorNumbers = group.map(\.collectorNumber).sorted {
                    (Int($0.filter(\.isNumber)) ?? 0) < (Int($1.filter(\.isNumber)) ?? 0)
                }

                let id = "sld-\(firstNum)"
                let desc = known != nil
                    ? "\(group.count) basic lands by \(artistLabel). Sources: Scryfall."
                    : "\(group.count) basic lands by \(artistLabel) in the Secret Lair Drop series."

                categories.append(LandCategory(
                    id: id,
                    name: dropName,
                    iconName: icon,
                    description: desc,
                    cardNames: cardNames,
                    setCodes: ["sld"],
                    collectorNumbers: collectorNumbers
                ))
            }

            cachedSecretLairDrops = categories
            return categories
        } catch {
            print("[DynamicListService] Failed to fetch SLD basics: \(error)")
            return []
        }
    }
}
