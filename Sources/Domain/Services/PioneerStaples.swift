import Foundation

enum PioneerStaples {
    static let all: [LandCategory] = [creatures, spells, lands, artifactsEnchantments]

    static let creatures = LandCategory(
        id: "pioneer-creatures", name: "Pioneer Staple Creatures", iconName: "figure.stand",
        description: "Format-defining creatures in Pioneer.",
        cardNames: ["Amalia Benavides Aguirre", "Monastery Swiftspear", "Soul-Scar Mage", "Ledger Shredder", "Thing in the Ice", "Arclight Phoenix", "Sheoldred, the Apocalypse", "Greasefang, Okiba Boss", "Bloodtithe Harvester", "Elvish Mystic", "Llanowar Elves", "Old-Growth Troll", "Spell Queller", "Raffine, Scheming Seer", "Thalia, Guardian of Thraben", "Adeline, Resplendent Cathar", "Kalitas, Traitor of Ghet", "Tireless Tracker", "Torrential Gearhulk", "Cavalier of Thorns"])

    static let spells = LandCategory(
        id: "pioneer-spells", name: "Pioneer Staple Spells", iconName: "wand.and.stars",
        description: "Key spells and planeswalkers in Pioneer.",
        cardNames: ["Fatal Push", "Thoughtseize", "Supreme Verdict", "Dig Through Time", "Fiery Impulse", "Lightning Axe", "Temporal Trespass", "Opt", "Consider", "Abrupt Decay", "Mystical Dispute", "March of Otherworldly Light", "Vanishing Verse", "The Wandering Emperor", "Teferi, Hero of Dominaria"])

    static let lands = LandCategory(
        id: "pioneer-lands", name: "Pioneer Staple Lands", iconName: "map.fill",
        description: "Pioneer's manabase. Shocklands, pathways, and utility lands.",
        cardNames: ["Hallowed Fountain", "Watery Grave", "Blood Crypt", "Stomping Ground", "Temple Garden", "Godless Shrine", "Steam Vents", "Overgrown Tomb", "Sacred Foundry", "Breeding Pool", "Fabled Passage", "Mutavault", "Mana Confluence", "Nykthos, Shrine to Nyx", "Castle Locthwain"])

    static let artifactsEnchantments = LandCategory(
        id: "pioneer-artifacts", name: "Pioneer Staple Artifacts & Enchantments", iconName: "shield.fill",
        description: "Key artifacts and enchantments in Pioneer.",
        cardNames: ["Fable of the Mirror-Breaker", "Witch's Oven", "Cauldron Familiar", "Wedding Announcement", "Shark Typhoon", "Portable Hole", "Parhelion II"])
}
