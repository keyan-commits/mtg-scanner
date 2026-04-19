import Foundation

enum PremodernStaples {
    static let all: [LandCategory] = [creatures, spells, lands, artifactsEnchantments]

    static let creatures = LandCategory(
        id: "premodern-creatures", name: "Premodern Staple Creatures", iconName: "figure.stand",
        description: "Format-defining creatures in Premodern (4th Edition through Scourge, 1995-2003).",
        cardNames: ["Psychatog", "Wild Mongrel", "Nimble Mongoose", "Werebear", "Deranged Hermit", "Morphling", "Masticore", "Goblin Lackey", "Goblin Piledriver", "Goblin Warchief", "Jackal Pup", "Mogg Fanatic", "Quirion Ranger", "Birds of Paradise", "Wall of Blossoms", "Phantom Centaur", "Meddling Mage", "Mystic Enforcer", "Aquamoeba", "River Boa", "Hypnotic Specter", "Nether Spirit", "Phyrexian Negator", "Spiritmonger"])

    static let spells = LandCategory(
        id: "premodern-spells", name: "Premodern Staple Spells", iconName: "wand.and.stars",
        description: "The iconic spells of Premodern.",
        cardNames: ["Brainstorm", "Force of Will", "Counterspell", "Swords to Plowshares", "Lightning Bolt", "Duress", "Cabal Therapy", "Hymn to Tourach", "Dark Ritual", "Entomb", "Reanimate", "Exhume", "Fact or Fiction", "Accumulated Knowledge", "Impulse", "Armageddon", "Vindicate", "Wrath of God", "Firebolt", "Circular Logic", "Deep Analysis", "Living Wish", "Burning Wish", "Cunning Wish", "Snuff Out", "Smother"])

    static let lands = LandCategory(
        id: "premodern-lands", name: "Premodern Staple Lands", iconName: "map.fill",
        description: "Premodern's manabase. Duals, pain lands, Onslaught fetches, and utility lands.",
        cardNames: ["Wasteland", "Rishadan Port", "Mishra's Factory", "City of Traitors", "Ancient Tomb", "Treetop Village", "Faerie Conclave", "Polluted Delta", "Flooded Strand", "Bloodstained Mire", "Wooded Foothills", "Windswept Heath", "Adarkar Wastes", "Underground River", "Sulfurous Springs", "Karplusan Forest", "Brushland"])

    static let artifactsEnchantments = LandCategory(
        id: "premodern-artifacts", name: "Premodern Staple Artifacts & Enchantments", iconName: "shield.fill",
        description: "Key artifacts and enchantments in Premodern.",
        cardNames: ["Pernicious Deed", "Survival of the Fittest", "Sylvan Library", "Land Tax", "Necropotence", "Standstill", "Oath of Druids", "Cursed Scroll", "Winter Orb", "Isochron Scepter", "Chrome Mox", "Mox Diamond", "Aether Vial", "Null Rod", "Goblin Bombardment", "Astral Slide", "Aluren"])
}
