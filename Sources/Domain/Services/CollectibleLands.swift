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
        description: "Extremely rare promo basics from the Guru program (1999-2001). Players earned points by teaching Magic to new players and received one random Guru land per 10 points. All five illustrated by Terese Nielsen depicting stages of a \"double eclipse.\" Among the most valuable basic lands ever printed — Island alone commands ~$1,200.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ],
        setCodes: ["pgru"]
    )

    // MARK: - APAC Lands

    static let apacLands = LandCategory(
        id: "apac-lands",
        name: "APAC Lands",
        iconName: "globe.asia.australia.fill",
        description: "Asia-Pacific promo basic lands (1998), distributed with Tempest booster box purchases in the Asia-Pacific region. Three sealed packs (Red, Blue, Clear) of 5 basics each, 15 total. Each card depicts a real-world location: Mt. Fuji, Great Wall of China, Banaue Rice Terraces (Philippines), Uluru (Australia), Hong Kong, Singapore's Merlion, and more.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ],
        setCodes: ["palp"]
    )

    // MARK: - Euro Lands

    static let euroLands = LandCategory(
        id: "euro-lands",
        name: "Euro Lands",
        iconName: "globe.europe.africa.fill",
        description: "European promo basic lands (2000), obtained by mailing booster box barcodes from Nemesis, Prophecy, and Invasion to regional distributors. Three series (Blue, Red, Purple packs) of 5 basics each, 15 total. Art by Scott Bailey, Kev Walker, Mike Ploog, Ben Thompson, and Eric Peterson depicting iconic European landmarks. The mail-in requirement made them scarcer than typical promos.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ],
        setCodes: ["pelp"]
    )

    // MARK: - Arena Promo Lands

    static let arenaPromoLands = LandCategory(
        id: "arena-promo-lands",
        name: "Arena Promo Lands",
        iconName: "trophy.fill",
        description: "Promo basics from the Arena League organized play program (1996-2006). The 1996 Tony Roberts cycle forms a panorama. Later years featured foil versions (1999-2002) and panoramic art by Rob Alexander (2003) and John Avon (2004, 2006). Earned by top-ranked players at weekly in-store events.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ],
        setCodes: ["pal99", "pal00", "pal01", "pal02", "pal03", "pal04", "pal05", "pal06", "parl"]
    )

    // MARK: - Un-Set Full-Art Lands

    static let unSetFullArtLands = LandCategory(
        id: "unset-full-art-lands",
        name: "Un-Set Full-Art Lands",
        iconName: "paintbrush.fill",
        description: "The original full-art lands. Unglued (1998) by Christopher Rush introduced full-art cards to Magic with distinctive oval frames. Unhinged (2004) by John Avon set the gold standard with border-hugging panoramic art. Unstable (2017), also by John Avon, pioneered truly borderless printing. All were black-bordered and tournament-legal despite being in silver-bordered joke sets.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ],
        setCodes: ["ugl", "unh", "ust"]
    )

    // MARK: - Zendikar Full-Art Lands

    static let zendikarFullArtLands = LandCategory(
        id: "zendikar-full-art-lands",
        name: "Zendikar Full-Art Lands",
        iconName: "photo.artframe",
        description: "Full-art basics from original Zendikar (2009) — the first full-art lands in a Standard-legal set. 20 unique arts (4 per basic type) by artists including John Avon, Jung Park, Vincent Proce, and Rob Alexander. Appeared randomly in booster packs as part of the set's \"lands matter\" theme. The set that brought full-art lands to the masses.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ],
        setCodes: ["zen"]
    )

    // MARK: - Snow-Covered Lands

    static let snowCoveredLands = LandCategory(
        id: "snow-covered-lands",
        name: "Snow-Covered Lands",
        iconName: "snowflake",
        description: "Snow-supertype basics that produce snow mana — mechanically distinct from regular basics. First appeared in Ice Age (1995), returned in Coldsnap (2006) which formalized the Snow supertype, then Modern Horizons (2019) with full-art versions, and Kaldheim (2021) which brought them back to Standard. Required for snow synergies like Arcum's Astrolabe and Ice-Fang Coatl.",
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
        description: "The first-ever \"man-land\" from Antiquities (1994), with four seasonal art variants by Kaja and Phil Foglio. Spring is common-rarity; Summer, Autumn, and Winter are uncommon. Winter is typically most valuable as its art was never reprinted. Collecting all four seasons is a classic MTG goal.",
        cardNames: [
            "Mishra's Factory",
        ],
        setCodes: ["atq"]
    )

    // MARK: - Strip Mine

    static let stripMine = LandCategory(
        id: "strip-mine",
        name: "Strip Mine",
        iconName: "hammer.fill",
        description: "Iconic land destruction from Antiquities (1994), with four art variants by Daniel Gelon depicting stages of strip mining. One common, three uncommon. The \"tower\" variant (Version C) is typically most sought after. Banned in Legacy, restricted in Vintage — one of the most powerful lands ever printed.",
        cardNames: [
            "Strip Mine",
        ],
        setCodes: ["atq"]
    )

    // MARK: - Alpha/Beta Basic Lands

    static let alphaBetaBasicLands = LandCategory(
        id: "alpha-beta-basics",
        name: "Alpha/Beta Basic Lands",
        iconName: "a.circle.fill",
        description: "The very first basic lands ever printed (1993). Alpha (~2.6M cards total) has 2 arts per type with distinctively rounded corners. Beta (~7.8M cards) added a 3rd art per type that was accidentally omitted from Alpha. Both black-bordered; art by the original 25-artist pool including Mark Poole, Jesper Myrfors, and Rob Alexander. Near-mint copies are exceptionally rare.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ],
        setCodes: ["lea", "leb"]
    )

    // MARK: - Zendikar Expeditions (BFZ)

    static let zendikarExpeditionsBFZ = LandCategory(
        id: "expeditions-bfz",
        name: "Zendikar Expeditions (BFZ)",
        iconName: "sparkles",
        description: "Masterpiece Series from Battle for Zendikar (2015) — the first-ever Masterpiece cards. 25 premium full-art foils with hedron-themed frames, found at ~1 in 144 boosters. Includes all 10 fetchlands, 10 shocklands, and 5 BFZ tangolands. English only. Retroactively classified as the original Masterpiece Series.",
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
        ],
        setCodes: ["exp"]
    )

    // MARK: - Zendikar Expeditions (OGW)

    static let zendikarExpeditionsOGW = LandCategory(
        id: "expeditions-ogw",
        name: "Zendikar Expeditions (OGW)",
        iconName: "sparkles",
        description: "Masterpiece Series from Oath of the Gatewatch (2016), completing the 45-card Expeditions set. 20 premium full-art foils at ~1 in 144 boosters. Features 10 Shadowmoor/Eventide filter lands plus iconic utility lands including Ancient Tomb, Wasteland, Strip Mine, Eye of Ugin, and Horizon Canopy.",
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
        ],
        setCodes: ["exp"]
    )

    // MARK: - Zendikar Rising Expeditions

    static let zendikarRisingExpeditions = LandCategory(
        id: "znr-expeditions",
        name: "Zendikar Rising Expeditions",
        iconName: "star.fill",
        description: "30 premium lands from Zendikar Rising (2020). Unlike 2015 Expeditions, these were guaranteed box toppers (1 per Draft/Set box, 2 per Collector box). Foil versions exclusive to Collector Boosters (~1 in 6 packs). Includes all 10 fetchlands, 5 Battlebond lands, and utility staples like Cavern of Souls, Ancient Tomb, and Prismatic Vista.",
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
        ],
        setCodes: ["zne"]
    )

    // MARK: - Secret Lair Lands

    static let secretLairLands = LandCategory(
        id: "secret-lair-lands",
        name: "Secret Lair Lands",
        iconName: "lock.open.fill",
        description: "Premium basics from Secret Lair direct-to-consumer drops (2019-present). Hundreds of unique printings across 70+ drops featuring guest artists and IP crossovers. Notable drops include The Tokyo Lands (~$75/card), Godzilla Lands (Japanese-only foils), Full-Text Lands, and Artist Series by John Avon, Seb McKinnon, and others. Available in foil and non-foil.",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ],
        setCodes: ["sld", "slu", "slc"]
    )

    // MARK: - Judge Promo Lands

    static let judgePromoLands = LandCategory(
        id: "judge-promo-lands",
        name: "Judge Promo Lands",
        iconName: "person.badge.shield.checkmark.fill",
        description: "Full-art foil panorama basics by Terese Nielsen, sent to all certified judges prior to July 2014 as a sealed 5-card set. The five cards form a continuous panorama. Among the most expensive basic lands — Island commands ~$150+. Nielsen also sold 250 limited-edition canvas prints of the full panorama. Part of the broader Judge Gift program (1998-present).",
        cardNames: [
            "Plains",
            "Island",
            "Swamp",
            "Mountain",
            "Forest",
        ],
        setCodes: ["jgp", "g99", "g00", "g01", "g02", "g03", "g04", "g05", "g06", "g07", "g08", "g09", "g10", "g11", "j12", "j13", "j14", "j15", "j16", "j17", "j18", "j19", "j20", "pj21", "p22", "p23"]
    )

    // MARK: - Iconic Reserved List Lands

    static let iconicReservedListLands = LandCategory(
        id: "reserved-list-lands",
        name: "Iconic Reserved List Lands",
        iconName: "lock.fill",
        description: "Lands on the Reserved List — Wizards' 1996 promise to never reprint these cards. Includes all 10 original dual lands (Revised, ~$200-$800 each), the Urza's Saga \"Cradle cycle\" (Gaea's Cradle ~$1,200), and other scarce early-era lands. Prices can only increase as supply dwindles through attrition.",
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
        description: "Format staples and iconic lands not on the Reserved List but still commanding premium prices. Includes Legacy/Vintage pillars (Wasteland, Karakas, The Tabernacle at Pendrell Vale), Modern staples (Cavern of Souls, Urza's Saga), and the Power Nine-adjacent trio from Arabian Nights (Bazaar of Baghdad, Library of Alexandria, Mishra's Workshop).",
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
