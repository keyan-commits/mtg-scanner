import Foundation

enum StandardStaples {
    static let all: [LandCategory] = [creatures, spells, lands, artifactsEnchantments]

    static let creatures = LandCategory(
        id: "standard-creatures", name: "Standard Staple Creatures", iconName: "figure.stand",
        description: "Top creatures in current Standard (2024-2025).",
        cardNames: ["Sheoldred, the Apocalypse", "Atraxa, Grand Unifier", "Deep-Cavern Bat", "Preacher of the Schism", "Glissa Sunslayer", "Mosswood Dreadknight", "Sentinel of the Nameless City", "Raffine, Scheming Seer", "Overlord of the Hauntwoods", "Overlord of the Mistmoors", "Enduring Curiosity", "Enduring Innocence", "Enduring Courage", "Heartfire Hero", "Screaming Nemesis", "Phyrexian Fleshgorger"])

    static let spells = LandCategory(
        id: "standard-spells", name: "Standard Staple Spells", iconName: "wand.and.stars",
        description: "Key spells in current Standard.",
        cardNames: ["Go for the Throat", "Cut Down", "No More Lies", "Sunfall", "Bitter Triumph", "Get Lost", "Torch the Tower", "Negate", "Make Disappear", "Brotherhood's End", "Temporary Lockdown"])

    static let lands = LandCategory(
        id: "standard-lands", name: "Standard Staple Lands", iconName: "map.fill",
        description: "Current Standard manabase staples.",
        cardNames: ["Restless Anchorage", "Restless Cottage", "Restless Vents", "Restless Fortress", "Restless Ridgeline", "Cavern of Souls", "Copperline Gorge", "Darkslick Shores", "Seachrome Coast", "Blackcleave Cliffs", "Razorverge Thicket", "Mirrex"])

    static let artifactsEnchantments = LandCategory(
        id: "standard-artifacts", name: "Standard Staple Artifacts & Enchantments", iconName: "shield.fill",
        description: "Key artifacts, enchantments, and planeswalkers in Standard.",
        cardNames: ["Virtue of Loyalty", "Virtue of Persistence", "Up the Beanstalk", "The Wandering Emperor", "Kaito, Bane of Nightmares", "Wedding Announcement", "Leyline of the Guildpact"])
}
