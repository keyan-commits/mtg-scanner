import Foundation

// MARK: - Land Category

/// A curated category of special MTG lands (duals, fetches, shocks, etc.).
/// Each category is a browsable page in the "Lists (Lands)" section with
/// list/visual toggle and tappable card names that resolve via the local
/// Scryfall DB.
struct LandCategory: Identifiable, Sendable {
    let id: String
    let name: String
    let iconName: String
    let description: String
    /// Every card name in this category. Names must match the local
    /// Scryfall DB (English canonical names).
    let cardNames: [String]
    /// When non-empty, only show printings from these Scryfall set codes.
    /// Used by collectible land categories (Guru, APAC, Euro, etc.) so
    /// "Plains" resolves to the correct premium printing, not a generic one.
    let setCodes: [String]
    /// When non-empty, further filter printings to these collector numbers.
    /// Used by Secret Lair drops where all share set code "sld" but each
    /// drop occupies a distinct collector-number range.
    let collectorNumbers: [String]

    init(id: String, name: String, iconName: String, description: String, cardNames: [String], setCodes: [String] = [], collectorNumbers: [String] = []) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.description = description
        self.cardNames = cardNames
        self.setCodes = setCodes
        self.collectorNumbers = collectorNumbers
    }
}

// MARK: - All land categories

enum LandLists {

    static let all: [LandCategory] = [
        originalDuals,
        fetchLands,
        slowFetches,
        shockLands,
        painLands,
        fastLands,
        checkLands,
        filterLands,
        horizonLands,
        pathwayLands,
        triomes,
        triLands,
        bounceLands,
        creatureLands,
        channelLands,
        scryLands,
        surveyLands,
        battleLands,
        slowLands,
        revealLands,
        cyclingDuals,
        bondLands,
        rainbowLands,
        utilityLands,
    ]

    // MARK: - Original Dual Lands (ABUR)

    static let originalDuals = LandCategory(
        id: "duals",
        name: "Original Dual Lands",
        iconName: "crown.fill",
        description: "The 10 original Alpha/Beta/Unlimited/Revised dual lands. Two basic land types with no drawback — the gold standard of mana fixing. Reserved List, never reprinted.",
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

    // MARK: - Fetch Lands

    static let fetchLands = LandCategory(
        id: "fetches",
        name: "Fetch Lands",
        iconName: "magnifyingglass",
        description: "Sacrifice, pay 1 life: search your library for a land with a specific basic land type. The most-played nonbasic lands in competitive Magic — they fix mana, shuffle your library, and fuel delve/delirium.",
        cardNames: [
            "Polluted Delta",
            "Flooded Strand",
            "Bloodstained Mire",
            "Wooded Foothills",
            "Windswept Heath",
            "Marsh Flats",
            "Scalding Tarn",
            "Verdant Catacombs",
            "Arid Mesa",
            "Misty Rainforest",
        ]
    )

    static let slowFetches = LandCategory(
        id: "slow-fetches",
        name: "Basic-Only Fetch Lands",
        iconName: "magnifyingglass.circle",
        description: "Sacrifice to search for a basic land only — can NOT fetch duals, shocks, or triomes. Prismatic Vista pays 1 life but enters untapped. The rest enter tapped. Budget alternatives to the real fetch lands.",
        cardNames: [
            "Prismatic Vista",
            "Fabled Passage",
            "Bad River",
            "Flood Plain",
            "Rocky Tar Pit",
            "Mountain Valley",
            "Grasslands",
            "Evolving Wilds",
            "Terramorphic Expanse",
        ]
    )

    // MARK: - Shock Lands

    static let shockLands = LandCategory(
        id: "shocks",
        name: "Shock Lands",
        iconName: "bolt.fill",
        description: "Enter tapped unless you pay 2 life. Two basic land types — fetchable and Modern-legal. The backbone of Modern and Pioneer mana bases.",
        cardNames: [
            "Hallowed Fountain",
            "Watery Grave",
            "Blood Crypt",
            "Stomping Ground",
            "Temple Garden",
            "Godless Shrine",
            "Steam Vents",
            "Overgrown Tomb",
            "Sacred Foundry",
            "Breeding Pool",
        ]
    )

    // MARK: - Pain Lands

    static let painLands = LandCategory(
        id: "pain",
        name: "Pain Lands",
        iconName: "heart.slash.fill",
        description: "Tap for colorless freely, or tap and take 1 damage for one of two colors. Reliable untapped mana fixing with a small life cost.",
        cardNames: [
            "Adarkar Wastes",
            "Underground River",
            "Sulfurous Springs",
            "Karplusan Forest",
            "Brushland",
            "Caves of Koilos",
            "Shivan Reef",
            "Llanowar Wastes",
            "Battlefield Forge",
            "Yavimaya Coast",
        ]
    )

    // MARK: - Fast Lands

    static let fastLands = LandCategory(
        id: "fast",
        name: "Fast Lands",
        iconName: "hare.fill",
        description: "Enter untapped if you control two or fewer other lands. Perfect for aggressive decks that need mana on turns 1-3.",
        cardNames: [
            "Seachrome Coast",
            "Darkslick Shores",
            "Blackcleave Cliffs",
            "Copperline Gorge",
            "Razorverge Thicket",
            "Concealed Courtyard",
            "Spirebluff Canal",
            "Blooming Marsh",
            "Inspiring Vantage",
            "Botanical Sanctum",
        ]
    )

    // MARK: - Check Lands

    static let checkLands = LandCategory(
        id: "check",
        name: "Check Lands",
        iconName: "checkmark.circle.fill",
        description: "Enter untapped if you control a land with a matching basic land type. Pair well with shock lands and original duals.",
        cardNames: [
            "Glacial Fortress",
            "Drowned Catacomb",
            "Dragonskull Summit",
            "Rootbound Crag",
            "Sunpetal Grove",
            "Isolated Chapel",
            "Sulfur Falls",
            "Woodland Cemetery",
            "Clifftop Retreat",
            "Hinterland Harbor",
        ]
    )

    // MARK: - Filter Lands

    static let filterLands = LandCategory(
        id: "filter",
        name: "Filter Lands",
        iconName: "line.3.horizontal.decrease.circle.fill",
        description: "Tap for colorless; or pay 1 generic, tap: add two mana in any combination of two colors. Excellent color fixing for multicolor-heavy decks.",
        cardNames: [
            "Mystic Gate",
            "Sunken Ruins",
            "Graven Cairns",
            "Fire-Lit Thicket",
            "Wooded Bastion",
            "Fetid Heath",
            "Cascade Bluffs",
            "Twilight Mire",
            "Rugged Prairie",
            "Flooded Grove",
        ]
    )

    // MARK: - Pathway Lands (Zendikar Rising)

    static let pathwayLands = LandCategory(
        id: "pathways",
        name: "Pathway Lands",
        iconName: "arrow.left.arrow.right",
        description: "Modal double-faced lands — choose which color side to play. Always enter untapped but only produce one color once played. Pioneer and Standard staples.",
        cardNames: [
            "Brightclimb Pathway",
            "Clearwater Pathway",
            "Blightstep Pathway",
            "Cragcrown Pathway",
            "Branchloft Pathway",
            "Needleverge Pathway",
            "Riverglide Pathway",
            "Darkbore Pathway",
            "Barkchannel Pathway",
            "Hengegate Pathway",
        ]
    )

    // MARK: - Triomes (Ikoria + Streets of New Capenna)

    static let triomes = LandCategory(
        id: "triomes",
        name: "Triomes",
        iconName: "triangle.fill",
        description: "Three-color lands with three basic land types — fetchable! Enter tapped but cycle for 3. The premier three-color fixing in Modern and Legacy.",
        cardNames: [
            // Ikoria Triomes
            "Indatha Triome",
            "Ketria Triome",
            "Raugrin Triome",
            "Savai Triome",
            "Zagoth Triome",
            // Streets of New Capenna Triomes
            "Jetmir's Garden",
            "Raffine's Tower",
            "Spara's Headquarters",
            "Xander's Lounge",
            "Ziatora's Proving Ground",
        ]
    )

    // MARK: - Bounce Lands (Ravnica Karoo cycle)

    static let bounceLands = LandCategory(
        id: "bounce",
        name: "Bounce Lands",
        iconName: "arrow.uturn.backward",
        description: "Enter tapped, return a land you control to hand. Tap for two colors. Net mana-positive but tempo-negative. Pauper staples.",
        cardNames: [
            "Azorius Chancery",
            "Dimir Aqueduct",
            "Rakdos Carnarium",
            "Gruul Turf",
            "Selesnya Sanctuary",
            "Orzhov Basilica",
            "Izzet Boilerworks",
            "Golgari Rot Farm",
            "Boros Garrison",
            "Simic Growth Chamber",
        ]
    )

    // MARK: - Creature Lands (Man-lands)

    static let creatureLands = LandCategory(
        id: "creature-lands",
        name: "Creature Lands",
        iconName: "figure.run",
        description: "Lands that can become creatures until end of turn. Dodge sorcery-speed removal and act as finishers in control decks.",
        cardNames: [
            "Celestial Colonnade",
            "Creeping Tar Pit",
            "Lavaclaw Reaches",
            "Raging Ravine",
            "Stirring Wildwood",
            "Shambling Vent",
            "Wandering Fumarole",
            "Hissing Quagmire",
            "Needle Spires",
            "Lumbering Falls",
            // Classic
            "Mutavault",
            "Mishra's Factory",
            "Treetop Village",
            "Faerie Conclave",
            "Blinkmoth Nexus",
            "Inkmoth Nexus",
            // Misc
            "Den of the Bugbear",
            "Hive of the Eye Tyrant",
            "Hall of Storm Giants",
            "Lair of the Hydra",
            "Cave of the Frost Dragon",
        ]
    )

    // MARK: - Channel Lands (Kamigawa: Neon Dynasty)

    static let channelLands = LandCategory(
        id: "channel",
        name: "Channel Lands",
        iconName: "bolt.horizontal.fill",
        description: "Legendary lands that can be discarded from hand for a spell effect via Channel. Uncounterable utility that doesn't cost a card slot — just a land slot.",
        cardNames: [
            "Eiganjo, Seat of the Empire",
            "Otawara, Soaring City",
            "Takenuma, Abandoned Mire",
            "Sokenzan, Crucible of Defiance",
            "Boseiju, Who Endures",
        ]
    )

    // MARK: - Survey Lands (Surveil lands, various sets)

    static let surveyLands = LandCategory(
        id: "surveil",
        name: "Surveil Lands",
        iconName: "eye.fill",
        description: "Enter tapped, surveil 1 when they enter. Two-color fixing with deck manipulation. Standard and Pioneer staples from Murders at Karlov Manor.",
        cardNames: [
            "Meticulous Archive",
            "Undercity Sewers",
            "Raucous Theater",
            "Commercial District",
            "Lush Portico",
            "Shadowy Backstreet",
            "Thundering Falls",
            "Underground Mortuary",
            "Elegant Parlor",
            "Hedge Maze",
        ]
    )

    // MARK: - Battle Lands (Tango Lands)

    static let battleLands = LandCategory(
        id: "battle",
        name: "Battle Lands",
        iconName: "shield.fill",
        description: "Enter tapped unless you control two or more basic lands. Two basic land types — fetchable. From Battle for Zendikar.",
        cardNames: [
            "Prairie Stream",
            "Sunken Hollow",
            "Smoldering Marsh",
            "Cinder Glade",
            "Canopy Vista",
        ]
    )

    // MARK: - Slow Lands (Innistrad: Midnight Hunt / Crimson Vow)

    static let slowLands = LandCategory(
        id: "slow",
        name: "Slow Lands",
        iconName: "tortoise.fill",
        description: "Enter untapped if you control two or fewer other lands (same as fast lands but from a different cycle). Modern and Standard playable.",
        cardNames: [
            "Deserted Beach",
            "Shipwreck Marsh",
            "Haunted Ridge",
            "Rockfall Vale",
            "Overgrown Farmland",
            "Shattered Sanctum",
            "Stormcarved Coast",
            "Deathcap Glade",
            "Sundown Pass",
            "Dreamroot Cascade",
        ]
    )

    // MARK: - Horizon / Canopy Lands

    static let horizonLands = LandCategory(
        id: "horizon",
        name: "Horizon Lands",
        iconName: "sunrise.fill",
        description: "Tap for one of two colors (pay 1 life). Pay 1 life, tap, sacrifice: draw a card. Lands that replace themselves — incredible in aggressive decks.",
        cardNames: [
            "Horizon Canopy",
            "Fiery Islet",
            "Nurturing Peatland",
            "Silent Clearing",
            "Sunbaked Canyon",
            "Waterlogged Grove",
        ]
    )

    // MARK: - Tri-Lands (Shards of Alara + Khans of Tarkir)

    static let triLands = LandCategory(
        id: "trilands",
        name: "Tri-Lands",
        iconName: "triangle",
        description: "Enter tapped, tap for one of three colors. Budget three-color fixing for Commander and casual play.",
        cardNames: [
            "Seaside Citadel",
            "Arcane Sanctum",
            "Crumbling Necropolis",
            "Savage Lands",
            "Jungle Shrine",
            "Mystic Monastery",
            "Opulent Palace",
            "Nomad Outpost",
            "Frontier Bivouac",
            "Sandsteppe Citadel",
        ]
    )

    // MARK: - Scry Lands (Temples)

    static let scryLands = LandCategory(
        id: "scry",
        name: "Scry Lands (Temples)",
        iconName: "eye.trianglebadge.exclamationmark",
        description: "Enter tapped, scry 1 when they enter. Smooth draws while fixing mana. Pioneer and Standard staples from Theros block.",
        cardNames: [
            "Temple of Enlightenment",
            "Temple of Deceit",
            "Temple of Malice",
            "Temple of Abandon",
            "Temple of Plenty",
            "Temple of Silence",
            "Temple of Epiphany",
            "Temple of Malady",
            "Temple of Triumph",
            "Temple of Mystery",
        ]
    )

    // MARK: - Reveal Lands (Shadows over Innistrad)

    static let revealLands = LandCategory(
        id: "reveal",
        name: "Reveal Lands",
        iconName: "hand.raised.fill",
        description: "Enter tapped unless you reveal a land with a matching basic type from your hand. Good in decks with many basics.",
        cardNames: [
            "Port Town",
            "Choked Estuary",
            "Foreboding Ruins",
            "Game Trail",
            "Fortified Village",
        ]
    )

    // MARK: - Cycling Dual Lands (Amonkhet)

    static let cyclingDuals = LandCategory(
        id: "cycling",
        name: "Cycling Dual Lands",
        iconName: "arrow.triangle.2.circlepath",
        description: "Two basic land types (fetchable!), always enter tapped. Cycling {2} lets you trade them for a card when you don't need more mana. Legacy and Modern playable via fetches.",
        cardNames: [
            "Irrigated Farmland",
            "Fetid Pools",
            "Canyon Slough",
            "Sheltered Thicket",
            "Scattered Groves",
        ]
    )

    // MARK: - Bond / Crowd Lands (Battlebond / Commander Legends)

    static let bondLands = LandCategory(
        id: "bond",
        name: "Bond Lands",
        iconName: "person.2.fill",
        description: "Enter untapped if you have two or more opponents. The premier Commander dual lands — always untapped in multiplayer.",
        cardNames: [
            "Sea of Clouds",
            "Morphic Pool",
            "Luxury Suite",
            "Spire Garden",
            "Bountiful Promenade",
            "Vault of Champions",
            "Training Center",
            "Undergrowth Stadium",
            "Spectator Seating",
            "Rejuvenating Springs",
        ]
    )

    // MARK: - Rainbow Lands (Five-Color)

    static let rainbowLands = LandCategory(
        id: "rainbow",
        name: "Rainbow Lands",
        iconName: "rainbow",
        description: "Produce any color of mana — perfect for 3+ color decks. Each has a different cost or restriction.",
        cardNames: [
            "City of Brass",
            "Mana Confluence",
            "Reflecting Pool",
            "Forbidden Orchard",
            "Exotic Orchard",
            "Gemstone Mine",
            "Tarnished Citadel",
            "Pillar of the Paruns",
            "Plaza of Heroes",
            "Command Tower",
            "Aether Hub",
            "Spire of Industry",
        ]
    )

    // MARK: - Utility Lands

    static let utilityLands = LandCategory(
        id: "utility",
        name: "Utility Lands",
        iconName: "wrench.and.screwdriver.fill",
        description: "Individually powerful lands that don't fit a dual-color cycle. Many are format-defining — Urza's Saga, Cavern of Souls, and Wasteland are among the most-played lands in competitive Magic.",
        cardNames: [
            "Urza's Saga",
            "Cavern of Souls",
            "Ancient Tomb",
            "Wasteland",
            "Strip Mine",
            "Field of the Dead",
            "Dark Depths",
            "Thespian's Stage",
            "Karakas",
            "Maze of Ith",
            "Rishadan Port",
            "Mutavault",
            "Inkmoth Nexus",
            "Blinkmoth Nexus",
            "Nykthos, Shrine to Nyx",
            "Gaea's Cradle",
            "Tolarian Academy",
            "Serra's Sanctum",
            "Phyrexian Tower",
            "Urborg, Tomb of Yawgmoth",
            "Yavimaya, Cradle of Growth",
            "Field of Ruin",
            "Ghost Quarter",
            "Blast Zone",
            "Inventors' Fair",
            "Academy Ruins",
            "Volrath's Stronghold",
            "Gemstone Caverns",
            "Hall of Heliod's Generosity",
            "Reliquary Tower",
        ]
    )
}
