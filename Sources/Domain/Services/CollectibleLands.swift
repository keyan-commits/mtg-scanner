import Foundation

// MARK: - Collectible Lands

/// Curated categories of collectible, premium, and iconic MTG lands.
/// These are lands sought after for their rarity, art, or historical
/// significance rather than competitive utility.
enum CollectibleLands {

    static let all: [LandCategory] = [
        guruLands,
        apacLands,
        euroLands,
        arenaPromoLands,
        unSetFullArtLands,
        zendikarFullArtLands,
        snowCoveredLands,
        mishrasFactory,
        stripMine,
        alphaBetaBasicLands,
        zendikarExpeditionsBFZ,
        zendikarExpeditionsOGW,
        zendikarRisingExpeditions,
        secretLairLands,
        judgePromoLands,
        iconicReservedListLands,
        otherIconicCollectibleLands,
    ]

    // MARK: - Guru Lands

    static let guruLands = LandCategory(
        id: "guru-lands",
        name: "Guru Lands",
        iconName: "star.circle.fill",
        description: "Extremely rare promo basics from the 1999 Guru program. Among the most valuable basic lands ever printed, featuring art by Terese Nielsen.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ]
    )

    // MARK: - APAC Lands

    static let apacLands = LandCategory(
        id: "apac-lands",
        name: "APAC Lands",
        iconName: "globe.asia.australia.fill",
        description: "Asia-Pacific promo basic lands (2000). Three series of 5 basics each featuring locations from the Asia-Pacific region. Scarce and collectible.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ]
    )

    // MARK: - Euro Lands

    static let euroLands = LandCategory(
        id: "euro-lands",
        name: "Euro Lands",
        iconName: "globe.europe.africa.fill",
        description: "European promo basic lands (2000). Three series featuring iconic European locations. Highly collectible alongside their APAC counterparts.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ]
    )

    // MARK: - Arena Promo Lands

    static let arenaPromoLands = LandCategory(
        id: "arena-promo-lands",
        name: "Arena Promo Lands",
        iconName: "trophy.fill",
        description: "Arena League promo basic lands distributed at in-store Arena League events in the early 2000s. Feature unique art not found in regular sets.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ]
    )

    // MARK: - Un-Set Full-Art Lands

    static let unSetFullArtLands = LandCategory(
        id: "unset-full-art-lands",
        name: "Un-Set Full-Art Lands",
        iconName: "paintbrush.fill",
        description: "Full-art basics from Unglued, Unhinged, and Unstable. The original full-art lands -- Unhinged basics by John Avon remain among the most popular lands ever.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ]
    )

    // MARK: - Zendikar Full-Art Lands

    static let zendikarFullArtLands = LandCategory(
        id: "zendikar-full-art-lands",
        name: "Zendikar Full-Art Lands",
        iconName: "photo.artframe",
        description: "Full-art basics from original Zendikar (2009). The first full-art basics in a tournament-legal set. Widely used and beloved for their striking landscapes.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ]
    )

    // MARK: - Snow-Covered Lands

    static let snowCoveredLands = LandCategory(
        id: "snow-covered-lands",
        name: "Snow-Covered Lands",
        iconName: "snowflake",
        description: "Snow basic lands from Ice Age, Coldsnap, and Modern Horizons. Required for snow synergies and mechanically distinct from regular basics.",
        cardNames: [
            "Snow-Covered Plains",
            "Snow-Covered Island",
            "Snow-Covered Swamp",
            "Snow-Covered Mountain",
            "Snow-Covered Forest",
        ]
    )

    // MARK: - Mishra's Factory

    static let mishrasFactory = LandCategory(
        id: "mishras-factory",
        name: "Mishra's Factory",
        iconName: "gearshape.2.fill",
        description: "The original creature land from Antiquities (1994). Four seasonal art variants (Spring, Summer, Autumn, Winter) make it a popular collectible.",
        cardNames: [
            "Mishra's Factory",
        ]
    )

    // MARK: - Strip Mine

    static let stripMine = LandCategory(
        id: "strip-mine",
        name: "Strip Mine",
        iconName: "hammer.fill",
        description: "Iconic land destruction from Antiquities. Four art variants depicting different stages of mining. Banned or restricted in most formats.",
        cardNames: [
            "Strip Mine",
        ]
    )

    // MARK: - Alpha/Beta Basic Lands

    static let alphaBetaBasicLands = LandCategory(
        id: "alpha-beta-basics",
        name: "Alpha/Beta Basic Lands",
        iconName: "a.circle.fill",
        description: "The original basic lands from Magic's first print runs (1993). Alpha cards are identifiable by their rounded corners. Graded copies command premium prices.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ]
    )

    // MARK: - Zendikar Expeditions (BFZ)

    static let zendikarExpeditionsBFZ = LandCategory(
        id: "expeditions-bfz",
        name: "Zendikar Expeditions (BFZ)",
        iconName: "sparkles",
        description: "Masterpiece Series from Battle for Zendikar. 25 premium full-art foil lands with the Zendikar Expeditions frame. Extremely rare booster pulls.",
        cardNames: [
            "Prairie Stream",
            "Sunken Hollow",
            "Smoldering Marsh",
            "Cinder Glade",
            "Canopy Vista",
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
            "Flooded Strand",
            "Polluted Delta",
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

    // MARK: - Zendikar Expeditions (OGW)

    static let zendikarExpeditionsOGW = LandCategory(
        id: "expeditions-ogw",
        name: "Zendikar Expeditions (OGW)",
        iconName: "sparkles",
        description: "Masterpiece Series from Oath of the Gatewatch. 20 premium full-art foil lands continuing the Expeditions series with utility and filter lands.",
        cardNames: [
            "Ancient Tomb",
            "Cascade Bluffs",
            "Dust Bowl",
            "Eye of Ugin",
            "Fetid Heath",
            "Fire-Lit Thicket",
            "Flooded Grove",
            "Forbidden Orchard",
            "Graven Cairns",
            "Horizon Canopy",
            "Kor Haven",
            "Mana Confluence",
            "Mystic Gate",
            "Rugged Prairie",
            "Strip Mine",
            "Sunken Ruins",
            "Tectonic Edge",
            "Twilight Mire",
            "Wasteland",
            "Wooded Bastion",
        ]
    )

    // MARK: - Zendikar Rising Expeditions

    static let zendikarRisingExpeditions = LandCategory(
        id: "znr-expeditions",
        name: "Zendikar Rising Expeditions",
        iconName: "star.fill",
        description: "30 premium box-topper lands from Zendikar Rising. Full-art treatments of fetch lands, pathway lands, and other staples with the hedron frame.",
        cardNames: [
            "Arid Mesa",
            "Marsh Flats",
            "Misty Rainforest",
            "Scalding Tarn",
            "Verdant Catacombs",
            "Flooded Strand",
            "Polluted Delta",
            "Bloodstained Mire",
            "Wooded Foothills",
            "Windswept Heath",
            "Prismatic Vista",
            "Fabled Passage",
            "Morphic Pool",
            "Luxury Suite",
            "Bountiful Promenade",
            "Sea of Clouds",
            "Spire Garden",
            "Cavern of Souls",
            "Strip Mine",
            "Wasteland",
            "Ancient Tomb",
            "Celestial Colonnade",
            "Creeping Tar Pit",
            "Lavaclaw Reaches",
            "Raging Ravine",
            "Stirring Wildwood",
            "Valakut, the Molten Pinnacle",
            "Sejiri Steppe",
            "Jwari Ruins",
            "Emeria, the Sky Ruin",
        ]
    )

    // MARK: - Secret Lair Lands

    static let secretLairLands = LandCategory(
        id: "secret-lair-lands",
        name: "Secret Lair Lands",
        iconName: "lock.open.fill",
        description: "Premium basic lands from various Secret Lair drops. Feature unique art styles from guest artists and special collaborations.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ]
    )

    // MARK: - Judge Promo Lands

    static let judgePromoLands = LandCategory(
        id: "judge-promo-lands",
        name: "Judge Promo Lands",
        iconName: "person.badge.shield.checkmark.fill",
        description: "Full-art foil basic lands given to certified judges. Limited distribution makes them sought-after collectibles.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ]
    )

    // MARK: - Iconic Reserved List Lands

    static let iconicReservedListLands = LandCategory(
        id: "reserved-list-lands",
        name: "Iconic Reserved List Lands",
        iconName: "lock.fill",
        description: "Collectible lands on the Reserved List that will never be reprinted. Includes original duals, the Cradle cycle, and other scarce early-era lands.",
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
            "Gaea's Cradle",
            "Tolarian Academy",
            "Serra's Sanctum",
            "Phyrexian Tower",
            "Lake of the Dead",
            "Volrath's Stronghold",
            "City of Traitors",
            "Gemstone Mine",
            "Undiscovered Paradise",
            "Rainbow Vale",
            "Elephant Graveyard",
        ]
    )

    // MARK: - Other Iconic Collectible Lands

    static let otherIconicCollectibleLands = LandCategory(
        id: "other-iconic-lands",
        name: "Other Iconic Collectible Lands",
        iconName: "star.square.fill",
        description: "Highly sought-after lands not on the Reserved List. Format staples, iconic designs, and premium printings that hold significant collector value.",
        cardNames: [
            "Cavern of Souls",
            "Ancient Tomb",
            "Wasteland",
            "Karakas",
            "Rishadan Port",
            "Maze of Ith",
            "Dark Depths",
            "Urza's Saga",
            "The Tabernacle at Pendrell Vale",
            "Bazaar of Baghdad",
            "Library of Alexandria",
            "Mishra's Workshop",
            "Nykthos, Shrine to Nyx",
            "Urborg, Tomb of Yawgmoth",
            "Yavimaya, Cradle of Growth",
            "Boseiju, Who Endures",
            "Otawara, Soaring City",
        ]
    )
}
