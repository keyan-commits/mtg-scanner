import Foundation

enum ModernStaples {
    static let all: [LandCategory] = [creatures, spells, lands, artifactsEnchantments]

    static let creatures = LandCategory(
        id: "modern-creatures", name: "Modern Staple Creatures", iconName: "figure.stand",
        description: "Format-defining creatures in Modern. From Ragavan and Orcish Bowmasters to Murktide Regent and the Elemental Incarnation cycle.",
        cardNames: ["Ragavan, Nimble Pilferer", "Orcish Bowmasters", "Murktide Regent", "Grief", "Solitude", "Subtlety", "Endurance", "Omnath, Locus of Creation", "Yawgmoth, Thran Physician", "Dragon's Rage Channeler", "Stoneforge Mystic", "Thought-Knot Seer", "Primeval Titan", "Monastery Swiftspear", "Goblin Guide", "Death's Shadow", "Archon of Cruelty", "Amalia Benavides Aguirre", "Thalia, Guardian of Thraben", "Emrakul, the Aeons Torn", "Grist, the Hunger Tide", "Seasoned Pyromancer", "Puresteel Paladin"])

    static let spells = LandCategory(
        id: "modern-spells", name: "Modern Staple Spells", iconName: "wand.and.stars",
        description: "Key instants, sorceries, and planeswalkers in Modern.",
        cardNames: ["Lightning Bolt", "Counterspell", "Unholy Heat", "Fatal Push", "Prismatic Ending", "Thoughtseize", "Inquisition of Kozilek", "March of Otherworldly Light", "Collected Company", "Living End", "Crashing Footfalls", "Force of Negation", "Path to Exile", "Spell Pierce", "Terminate", "Teferi, Time Raveler", "Wrenn and Six"])

    static let lands = LandCategory(
        id: "modern-lands", name: "Modern Staple Lands", iconName: "map.fill",
        description: "Essential lands in Modern. Fetchlands, Urza's Saga, channel lands, and utility lands.",
        cardNames: ["Urza's Saga", "Boseiju, Who Endures", "Otawara, Soaring City", "Cavern of Souls", "Gemstone Caverns", "Inkmoth Nexus", "Blast Zone", "Flooded Strand", "Polluted Delta", "Scalding Tarn", "Misty Rainforest", "Verdant Catacombs", "Arid Mesa", "Marsh Flats", "Bloodstained Mire", "Wooded Foothills", "Windswept Heath"])

    static let artifactsEnchantments = LandCategory(
        id: "modern-artifacts", name: "Modern Staple Artifacts & Enchantments", iconName: "shield.fill",
        description: "Format-warping artifacts and enchantments in Modern.",
        cardNames: ["The One Ring", "Chalice of the Void", "Amulet of Vigor", "Colossus Hammer", "Sigarda's Aid", "Engineered Explosives", "Blood Moon", "Spreading Seas", "Leyline Binding", "Leyline of the Guildpact"])
}
