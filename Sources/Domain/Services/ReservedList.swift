import Foundation

// MARK: - Reserved List

/// Curated categories of notable cards on the Reserved List — Wizards'
/// 1996 promise to never reprint these cards. Organized by card type
/// and significance. Not exhaustive (~600 total on the RL), but covers
/// the most valuable, played, and collectible entries.
enum ReservedList {

    static let all: [LandCategory] = [
        powerNine,
        originalDualLands,
        iconicArtifacts,
        iconicEnchantments,
        iconicCreatures,
        iconicSpells,
        iconicLands,
    ]

    // MARK: - Power Nine

    static let powerNine = LandCategory(
        id: "rl-power-nine",
        name: "Power Nine",
        iconName: "crown.fill",
        description: "The nine most powerful cards ever printed (1993). Black Lotus and the five Moxen provide free mana; Ancestral Recall, Time Walk, and Timetwister are absurdly undercosted effects. All restricted in Vintage, banned everywhere else. Alpha copies are among the most expensive trading cards in the world. Sources: MTG Wiki, Scryfall.",
        cardNames: [
            "Black Lotus",
            "Mox Pearl",
            "Mox Sapphire",
            "Mox Jet",
            "Mox Ruby",
            "Mox Emerald",
            "Ancestral Recall",
            "Time Walk",
            "Timetwister",
        ]
    )

    // MARK: - Original Dual Lands

    static let originalDualLands = LandCategory(
        id: "rl-dual-lands",
        name: "Original Dual Lands",
        iconName: "circle.lefthalf.filled",
        description: "The ten original dual lands from Alpha/Beta/Unlimited/Revised (1993-1994). Two basic land types with no drawback — strictly superior to any subsequent dual land cycle. Backbone of Legacy and Vintage manabases. Revised printings ($200-800); Alpha/Beta ($2,000-30,000+). Sources: MTG Wiki, Scryfall.",
        cardNames: [
            "Tundra",
            "Underground Sea",
            "Badlands",
            "Taiga",
            "Savannah",
            "Scrubland",
            "Volcanic Island",
            "Bayou",
            "Plateau",
            "Tropical Island",
        ]
    )

    // MARK: - Iconic Artifacts

    static let iconicArtifacts = LandCategory(
        id: "rl-artifacts",
        name: "Iconic Reserved Artifacts",
        iconName: "gearshape.fill",
        description: "The most valuable and played artifacts on the Reserved List. Includes fast mana (Mox Diamond, Grim Monolith, Lion's Eye Diamond), combo pieces (Memory Jar, Metalworker), and format staples. Sources: MTG Wiki, Scryfall.",
        cardNames: [
            "Lion's Eye Diamond",
            "Mox Diamond",
            "Grim Monolith",
            "Memory Jar",
            "Metalworker",
            "Helm of Obedience",
            "Null Rod",
            "Phyrexian Devourer",
            "Lotus Petal",
            "Mana Vault",
            "Candelabra of Tawnos",
            "Copy Artifact",
            "Gilded Drake",
            "Cursed Scroll",
            "Karn, Silver Golem",
        ]
    )

    // MARK: - Iconic Enchantments

    static let iconicEnchantments = LandCategory(
        id: "rl-enchantments",
        name: "Iconic Reserved Enchantments",
        iconName: "sparkles",
        description: "Premier enchantments on the Reserved List. Includes Legacy/Vintage staples, devastating lock pieces, and cards that define entire strategies. Many from the early 'enchant world' era. Sources: MTG Wiki, Scryfall.",
        cardNames: [
            "Moat",
            "The Abyss",
            "Chains of Mephistopheles",
            "Nether Void",
            "In the Eye of Chaos",
            "Living Plane",
            "Replenish",
            "Aluren",
            "Earthcraft",
            "Recurring Nightmare",
            "Survival of the Fittest",
            "Dream Halls",
            "Yawgmoth's Bargain",
        ]
    )

    // MARK: - Iconic Creatures

    static let iconicCreatures = LandCategory(
        id: "rl-creatures",
        name: "Iconic Reserved Creatures",
        iconName: "figure.stand",
        description: "Notable creatures on the Reserved List. Combo enablers, format staples, and collectible legends from Magic's early history. Sources: MTG Wiki, Scryfall.",
        cardNames: [
            "Sliver Queen",
            "Phyrexian Dreadnought",
            "Palinchron",
            "Morphling",
            "Masticore",
            "Deranged Hermit",
            "Phyrexian Negator",
            "Thunder Dragon",
            "Avatar of Woe",
            "Multani, Maro-Sorcerer",
            "Rofellos, Llanowar Emissary",
            "Lin Sivvi, Defiant Hero",
            "Weathered Wayfarer",
        ]
    )

    // MARK: - Iconic Spells

    static let iconicSpells = LandCategory(
        id: "rl-spells",
        name: "Iconic Reserved Spells",
        iconName: "wand.and.stars",
        description: "Powerful instants and sorceries on the Reserved List. Format-defining effects that shape Vintage, Legacy, and Commander. Several are banned or restricted across multiple formats. Sources: MTG Wiki, Scryfall.",
        cardNames: [
            "Yawgmoth's Will",
            "Time Spiral",
            "Wheel of Fortune",
            "Mind Over Matter",
            "Show and Tell",
            "Intuition",
            "Meditate",
            "Sneak Attack",
            "Natural Order",
            "Academy Rector",
            "Tinker",
            "Frantic Search",
            "Windfall",
        ]
    )

    // MARK: - Iconic Lands

    static let iconicLands = LandCategory(
        id: "rl-lands",
        name: "Reserved List Lands",
        iconName: "map.fill",
        description: "Non-dual lands on the Reserved List. Includes the Urza's Saga 'Cradle cycle' (among the most expensive non-Power cards), early utility lands, and unique effects that will never be reprinted. Sources: MTG Wiki, Scryfall.",
        cardNames: [
            "Gaea's Cradle",
            "Tolarian Academy",
            "Serra's Sanctum",
            "Phyrexian Tower",
            "Volrath's Stronghold",
            "Lake of the Dead",
            "City of Traitors",
            "Gemstone Mine",
            "Undiscovered Paradise",
            "Rainbow Vale",
            "Elephant Graveyard",
        ]
    )
}
