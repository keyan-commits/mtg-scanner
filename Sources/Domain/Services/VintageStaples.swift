import Foundation

enum VintageStaples {
    static let all: [LandCategory] = [creatures, spells, lands, artifactsEnchantments]

    static let creatures = LandCategory(
        id: "vintage-creatures", name: "Vintage Staple Creatures", iconName: "figure.stand",
        description: "Key creatures in Vintage beyond the Power Nine.",
        cardNames: ["Monastery Mentor", "Orcish Bowmasters", "Lodestone Golem", "Phyrexian Revoker", "Hollow One", "Hogaak, Arisen Necropolis", "Grief", "Golgari Grave-Troll", "Ichorid", "Narcomoeba", "Prized Amalgam", "Blightsteel Colossus"])

    static let spells = LandCategory(
        id: "vintage-spells", name: "Vintage Staple Spells", iconName: "wand.and.stars",
        description: "Format-defining spells in Vintage. Many restricted to one copy.",
        cardNames: ["Force of Will", "Force of Negation", "Mental Misstep", "Flusterstorm", "Brainstorm", "Ponder", "Preordain", "Gitaxian Probe", "Tinker", "Demonic Tutor", "Vampiric Tutor", "Mystical Tutor", "Yawgmoth's Will", "Treasure Cruise", "Dig Through Time", "Dark Ritual", "Swords to Plowshares", "Lightning Bolt", "Pyroblast", "Paradoxical Outcome", "Merchant Scroll"])

    static let lands = LandCategory(
        id: "vintage-lands", name: "Vintage Staple Lands", iconName: "map.fill",
        description: "Iconic Vintage lands. Many restricted.",
        cardNames: ["Bazaar of Baghdad", "Mishra's Workshop", "Strip Mine", "Wasteland", "Library of Alexandria", "Tolarian Academy", "Ancient Tomb", "Urza's Saga", "Boseiju, Who Endures", "Cavern of Souls"])

    static let artifactsEnchantments = LandCategory(
        id: "vintage-artifacts", name: "Vintage Staple Artifacts & Enchantments", iconName: "shield.fill",
        description: "The artifact-heavy backbone of Vintage. Many restricted.",
        cardNames: ["Mana Crypt", "Sol Ring", "Mana Vault", "Mox Opal", "Chrome Mox", "Mox Diamond", "Lotus Petal", "Sensei's Divining Top", "Trinisphere", "Thorn of Amethyst", "Sphere of Resistance", "Chalice of the Void", "The One Ring", "Time Vault", "Mystic Forge", "Null Rod", "Grafdigger's Cage"])
}
