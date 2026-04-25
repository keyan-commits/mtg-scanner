import Foundation

/// Curated categories of Japanese collectible MTG cards.
/// These are cards with significant premiums in Japanese printings,
/// Japanese-exclusive art, or historically important Japanese sets.
enum JapaneseCollectibles {

    static let all: [LandCategory] = [
        warAlternateArt,
        mysticalArchiveJP,
        japanShowcase,
        portalThreeKingdoms,
        godzillaSeries,
        japanPromos,
    ]

    // MARK: - War of the Spark Japanese Alternate Art

    static let warAlternateArt = LandCategory(
        id: "war-jp-alt-art",
        name: "WAR Japanese Alt-Art",
        iconName: "sparkles",
        description: "36 anime-style alternate art planeswalkers from War of the Spark, including the iconic Yoshitaka Amano Liliana. Found only in Japanese WAR boosters.",
        cardNames: [
            "Ajani, the Greathearted",
            "Angrath, Captain of Chaos",
            "Arlinn, Voice of the Pack",
            "Ashiok, Dream Render",
            "Chandra, Fire Artisan",
            "Davriel, Rogue Shadowmage",
            "Domri, Anarch of Bolas",
            "Dovin, Hand of Control",
            "Gideon Blackblade",
            "Huatli, the Sun's Heart",
            "Jace, Wielder of Mysteries",
            "Jaya, Venerated Firemage",
            "Jiang Yanggu, Wildcrafter",
            "Karn, the Great Creator",
            "Kasmina, Enigmatic Mentor",
            "Kiora, Behemoth Beckoner",
            "Kaya, Bane of the Dead",
            "Liliana, Dreadhorde General",
            "Nahiri, Storm of Stone",
            "Narset, Parter of Veils",
            "Nicol Bolas, Dragon-God",
            "Nissa, Who Shakes the World",
            "Ob Nixilis, the Hate-Twisted",
            "Ral, Storm Conduit",
            "Saheeli, Sublime Artificer",
            "Samut, Tyrant Smasher",
            "Sarkhan the Masterless",
            "Sorin, Vengeful Bloodlord",
            "Tamiyo, Collector of Tales",
            "Teferi, Time Raveler",
            "Teyo, the Shieldmage",
            "The Wanderer",
            "Tibalt, Rakish Instigator",
            "Ugin, the Ineffable",
            "Vivien, Champion of the Wilds",
            "Vraska, Swarm's Eminence",
        ],
        setCodes: ["war"]
    )

    // MARK: - Strixhaven Mystical Archive Japanese

    static let mysticalArchiveJP = LandCategory(
        id: "sta-jp-alt-art",
        name: "Mystical Archive JP",
        iconName: "scroll.fill",
        description: "63 instants and sorceries with ukiyo-e inspired Japanese art from Strixhaven Mystical Archive. Includes Silver Scroll Foil premium variants.",
        cardNames: [
            "Abundant Harvest", "Advent of the Wurm", "Agonizing Remorse",
            "Approach of the Second Sun", "Blue Sun's Zenith", "Brainstorm",
            "Channel", "Claim the Firstborn", "Clever Lumimancer",
            "Compulsive Research", "Counterspell", "Crux of Fate",
            "Cultivate", "Dark Ritual", "Day of Judgment",
            "Defiant Strike", "Demonic Tutor", "Despark",
            "Doom Blade", "Duress", "Eliminate",
            "Ephemerate", "Faithless Looting", "Gift of Estates",
            "Gods Willing", "Growth Spiral", "Grapeshot",
            "Harmonize", "Increasing Vengeance", "Inquisition of Kozilek",
            "Krosan Grip", "Lightning Bolt", "Lightning Helix",
            "Mana Tithe", "Memory Lapse", "Mind's Desire",
            "Mizzix's Mastery", "Natural Order", "Negate",
            "Opt", "Primal Command", "Putrefy",
            "Regrowth", "Revitalize", "Shock",
            "Sign in Blood", "Snakeskin Veil", "Stone Rain",
            "Strategic Planning", "Swords to Plowshares", "Tezzeret's Gambit",
            "Thrill of Possibility", "Time Warp", "Urza's Rage",
            "Vampiric Tutor", "Village Rites", "Whirlwind Denial",
        ],
        setCodes: ["sta"]
    )

    // MARK: - Japan Showcase (2024+)

    static let japanShowcase = LandCategory(
        id: "japan-showcase",
        name: "Japan Showcase",
        iconName: "star.circle.fill",
        description: "Special frame cards by Japanese artists found in Collector Boosters. Includes ultra-rare Fracture Foil variants with stained-glass effect. Sets: Duskmourn, Foundations, Aetherdrift, and more.",
        cardNames: [
            // Duskmourn notable cards
            "Overlord of the Hauntwoods",
            "Enduring Innocence",
            "Leyline of Resonance",
            // Foundations notable cards
            "Llanowar Elves",
            "Day of Judgment",
            "Omniscience",
        ],
        setCodes: ["dsk", "fdn"]
    )

    // MARK: - Portal Three Kingdoms

    static let portalThreeKingdoms = LandCategory(
        id: "portal-three-kingdoms",
        name: "Portal Three Kingdoms",
        iconName: "building.columns.fill",
        description: "Extremely rare 1999 starter set based on Romance of the Three Kingdoms. Printed primarily in Japanese and Chinese with a tiny English run. Contains Imperial Seal (~$1,600) and other unique cards.",
        cardNames: [
            "Imperial Seal",
            "Capture of Jingzhou",
            "Ravages of War",
            "Warrior's Oath",
            "Rolling Earthquake",
            "Burning of Xinye",
            "Zodiac Dragon",
            "Xiahou Dun, the One-Eyed",
            "Lu Bu, Master-at-Arms",
            "Dong Zhou, the Tyrant",
            "Sun Quan, Lord of Wu",
            "Cao Cao, Lord of Wei",
            "Liu Bei, Lord of Shu",
            "Guan Yu, Sainted Warrior",
            "Zhang Fei, Fierce Warrior",
            "Zhuge Jin, Wu Strategist",
        ],
        setCodes: ["ptk"]
    )

    // MARK: - Godzilla Series

    static let godzillaSeries = LandCategory(
        id: "godzilla-series",
        name: "Godzilla Series",
        iconName: "lizard.fill",
        description: "19 Godzilla alternate-name cards from Ikoria, including 3 Japanese-exclusive variants. Features iconic kaiju like Godzilla, Mothra, and King Ghidorah.",
        cardNames: [
            "Zilortha, Strength Incarnate",
            "Brokkos, Apex of Forever",
            "Illuna, Apex of Wishes",
            "Nethroi, Apex of Death",
            "Snapdax, Apex of the Hunt",
            "Vadrok, Apex of Thunder",
            "Luminous Broodmoth",
            "Yidaro, Wandering Monster",
            "Crystalline Giant",
            "Hangarback Walker",
        ],
        setCodes: ["iko"]
    )

    // MARK: - Japan Promos

    static let japanPromos = LandCategory(
        id: "japan-promos",
        name: "Japan Store Promos",
        iconName: "gift.fill",
        description: "Promotional cards distributed exclusively at Japanese game stores, events, and tournaments. Includes Planeswalker Championship and Friendly Match promos.",
        cardNames: [
            "Lightning Bolt",
            "Path to Exile",
            "Serum Visions",
            "Gitaxian Probe",
            "Thought Scour",
        ],
        setCodes: ["pjsc", "pf24", "pf23"]
    )
}
