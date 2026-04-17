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

    /// Returns Secret Lair basic land drops built from the database.
    /// Groups by artist name to auto-discover new drops.
    func secretLairDrops() async -> [LandCategory] {
        if let cached = cachedSecretLairDrops { return cached }
        guard let db = databaseManager else { return [] }

        do {
            let records = try await db.fetchSecretLairBasics()
            guard !records.isEmpty else { return [] }

            // Group by artist
            var byArtist: [String: [CardRecord]] = [:]
            for record in records {
                let artist = record.artist ?? "Unknown"
                byArtist[artist, default: []].append(record)
            }

            // Known artist → drop name mapping for nicer display
            let knownDrops: [String: (name: String, icon: String)] = [
                "Alayna Danner": ("Eldraine Wonderland / Alayna Danner", "wand.and.stars"),
                "Jubilee": ("Pixel Lands (Jubilee)", "square.grid.3x3.fill"),
                "ELK64": ("PixelSnowLands v2 (ELK64)", "snowflake.circle.fill"),
                "Jeanne D'Angelo": ("The Astrology Lands", "star.circle.fill"),
                "kozyndan": ("Special Guest: Kozyndan", "paintbrush.pointed.fill"),
                "Mark Riddick": ("Unfathomable Crushing Brutality", "bolt.fill"),
                "Ben Schnuck": ("Shades Not Included", "sun.max.fill"),
                "Gary Baseman": ("Featuring: Gary Baseman", "theatermasks.fill"),
                "JungShan": ("Featuring: JungShan", "mountain.2.fill"),
                "Bob Ross": ("Happy Little Gathering", "paintpalette.fill"),
                "Scott Balmer": ("The Strange Sands", "leaf.fill"),
                "Jon Vermilyea": ("Secret Lair x SpongeBob", "water.waves"),
                "Ashley Dreyfus": ("Flower Power", "camera.macro"),
                "Pedro Potier": ("Secret Lair x Spider-Man", "web.camera.fill"),
                "Arthur Yuan": ("D&D: Forgotten Realms Lands", "shield.fill"),
                "Kelogsloops": ("Special Guest: Kelogsloops", "drop.fill"),
            ]

            var categories: [LandCategory] = []

            for (artist, cards) in byArtist.sorted(by: { $0.value.first?.collectorNumber ?? "" < $1.value.first?.collectorNumber ?? "" }) {
                let known = knownDrops[artist]
                let dropName = known?.name ?? artist
                let icon = known?.icon ?? "paintbrush.fill"
                let isSnow = cards.first?.name.contains("Snow") ?? false

                let cardNames: [String]
                if isSnow {
                    cardNames = ["Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp", "Snow-Covered Mountain", "Snow-Covered Forest"]
                } else {
                    // Use unique names from this artist's cards
                    cardNames = Array(Set(cards.map(\.name))).sorted {
                        let order = ["Plains", "Island", "Swamp", "Mountain", "Forest"]
                        return (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99)
                    }
                }

                let collectorNumbers = cards.map(\.collectorNumber).sorted {
                    (Int($0.filter(\.isNumber)) ?? 0) < (Int($1.filter(\.isNumber)) ?? 0)
                }

                let id = "sld-\(artist.lowercased().replacingOccurrences(of: " ", with: "-"))"

                categories.append(LandCategory(
                    id: id,
                    name: dropName,
                    iconName: icon,
                    description: "\(cards.count) basic lands by \(artist) in the Secret Lair Drop series.",
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
