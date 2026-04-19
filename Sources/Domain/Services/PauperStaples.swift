import Foundation

enum PauperStaples {
    static let all: [LandCategory] = [creatures, spells, lands, artifactsEnchantments]

    static let creatures = LandCategory(
        id: "pauper-creatures", name: "Pauper Staple Creatures", iconName: "figure.stand",
        description: "Format-defining commons in Pauper.",
        cardNames: ["Monastery Swiftspear", "Goblin Blast-Runner", "Glint Hawk", "Kor Skyfisher", "Thraben Inspector", "Augur of Bolas", "Spellstutter Sprite", "Ninja of the Deep Hours", "Faerie Seer", "Gurmag Angler", "Tolarian Terror", "Myr Enforcer", "Frogmite", "Mulldrifter", "Thorn of the Black Rose", "Boarding Party", "Annoyed Altisaur", "Ornithopter", "Carapace Forger", "Ardent Recruit"])

    static let spells = LandCategory(
        id: "pauper-spells", name: "Pauper Staple Spells", iconName: "wand.and.stars",
        description: "Key commons that define Pauper's metagame.",
        cardNames: ["Lightning Bolt", "Galvanic Blast", "Cast Down", "Snuff Out", "Counterspell", "Brainstorm", "Ponder", "Preordain", "Blue Elemental Blast", "Red Elemental Blast", "Skred", "Chainer's Edict", "Firebolt", "Ephemerate", "Prismatic Strands", "Battle Screech", "Cleansing Wildfire"])

    static let lands = LandCategory(
        id: "pauper-lands", name: "Pauper Staple Lands", iconName: "map.fill",
        description: "Key lands in Pauper including artifact lands and bridges.",
        cardNames: ["Ash Barrens", "Bojuka Bog", "Seat of the Synod", "Vault of Whispers", "Great Furnace", "Tree of Tales", "Ancient Den", "Darksteel Citadel", "Silverbluff Bridge", "Razortide Bridge", "Rustvale Bridge", "Tanglepool Bridge", "Mistvault Bridge", "Drossforge Bridge"])

    static let artifactsEnchantments = LandCategory(
        id: "pauper-artifacts", name: "Pauper Staple Artifacts & Enchantments", iconName: "shield.fill",
        description: "Essential artifacts and enchantments in Pauper.",
        cardNames: ["Experimental Synthesizer", "Chromatic Star", "Ichor Wellspring", "Relic of Progenitus", "Prophetic Prism", "Abundant Growth", "Utopia Sprawl", "All That Glitters"])
}
