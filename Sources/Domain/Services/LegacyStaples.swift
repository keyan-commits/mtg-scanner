import Foundation

enum LegacyStaples {
    static let all: [LandCategory] = [creatures, spells, lands, artifactsEnchantments]

    static let creatures = LandCategory(
        id: "legacy-creatures", name: "Legacy Staple Creatures", iconName: "figure.stand",
        description: "Format-defining creatures in Legacy. Delver, Bowmasters, Stoneforge, and combo enablers.",
        cardNames: ["Orcish Bowmasters", "Murktide Regent", "Delver of Secrets", "Monastery Mentor", "Stoneforge Mystic", "True-Name Nemesis", "Thalia, Guardian of Thraben", "Mother of Runes", "Goblin Lackey", "Emrakul, the Aeons Torn", "Griselbrand", "Elvish Reclaimer", "Knight of the Reliquary", "Ragavan, Nimble Pilferer", "Endurance", "Solitude"])

    static let spells = LandCategory(
        id: "legacy-spells", name: "Legacy Staple Spells", iconName: "wand.and.stars",
        description: "The defining spells of Legacy. Force of Will, Brainstorm, and the best interaction in Magic.",
        cardNames: ["Force of Will", "Brainstorm", "Ponder", "Daze", "Swords to Plowshares", "Lightning Bolt", "Thoughtseize", "Hymn to Tourach", "Dark Ritual", "Entomb", "Reanimate", "Show and Tell", "Natural Order", "Green Sun's Zenith", "Terminus", "Council's Judgment", "Surgical Extraction", "Pyroblast", "Hydroblast", "Force of Negation", "Crop Rotation", "Life from the Loam", "Prismatic Ending", "Jace, the Mind Sculptor", "Teferi, Time Raveler", "Narset, Parter of Veils"])

    static let lands = LandCategory(
        id: "legacy-lands", name: "Legacy Staple Lands", iconName: "map.fill",
        description: "Legacy's iconic manabase. Dual lands, Wasteland, Dark Depths, and more.",
        cardNames: ["Wasteland", "Dark Depths", "Thespian's Stage", "Karakas", "Maze of Ith", "Ancient Tomb", "City of Traitors", "Urza's Saga", "Boseiju, Who Endures", "Cavern of Souls", "The Tabernacle at Pendrell Vale", "Flooded Strand", "Polluted Delta", "Scalding Tarn", "Misty Rainforest", "Verdant Catacombs", "Tundra", "Underground Sea", "Volcanic Island", "Tropical Island", "Bayou", "Badlands"])

    static let artifactsEnchantments = LandCategory(
        id: "legacy-artifacts", name: "Legacy Staple Artifacts & Enchantments", iconName: "shield.fill",
        description: "Key artifacts and enchantments in Legacy.",
        cardNames: ["Batterskull", "Kaldra Compleat", "Chalice of the Void", "Aether Vial", "Mox Diamond", "Lion's Eye Diamond", "Lotus Petal", "Chrome Mox", "Sylvan Library", "Blood Moon", "Back to Basics", "Carpet of Flowers", "The One Ring"])
}
