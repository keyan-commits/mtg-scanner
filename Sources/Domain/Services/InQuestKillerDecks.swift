import Foundation

// MARK: - InQuest Magazine Killer Decks

/// Iconic decklists from InQuest Gamer magazine's "Killer Decks" column
/// (1990s-2000s). Each deck is a LandCategory where cardNames contains
/// every unique card in the decklist. Tap any card to see its detail.
enum InQuestKillerDecks {

    static let all: [LandCategory] = [
        theDeck,
        sligh,
        necropotence,
        turboStasis,
        erhnamgeddon,
        suicideBlack,
        landTaxScrollRack,
        firesOfYavimaya,
        psychatog,
        ponza,
    ]

    static let theDeck = LandCategory(
        id: "inquest-the-deck",
        name: "The Deck (Weissman)",
        iconName: "crown.fill",
        description: "Brian Weissman's legendary draw-go control deck (1996). The original control archetype that defined Magic strategy. Type 1 (Vintage). Features Power Nine, Mana Drain, Serra Angel as the lone win condition.",
        cardNames: [
            "Ancestral Recall", "Time Walk", "Timetwister", "Black Lotus",
            "Mox Sapphire", "Mox Jet", "Mox Pearl", "Mox Ruby", "Mox Emerald",
            "Sol Ring", "Demonic Tutor", "Mind Twist", "Recall",
            "Counterspell", "Mana Drain", "Swords to Plowshares", "Disenchant",
            "Balance", "Moat", "Mirror Universe", "Serra Angel", "Braingeyser",
            "Red Elemental Blast", "Regrowth", "Wrath of God",
            "Disrupting Scepter", "Jayemdae Tome", "Ivory Tower",
            "City of Brass", "Tundra", "Underground Sea", "Volcanic Island",
            "Library of Alexandria", "Strip Mine",
        ]
    )

    static let sligh = LandCategory(
        id: "inquest-sligh",
        name: "Sligh (Red Aggro)",
        iconName: "flame.fill",
        description: "Paul Sligh / Jay Schneider's pioneering red aggro deck (1996). Invented the concept of the 'mana curve' — playing the most efficient creature at every mana cost. PTQ Atlanta winning list.",
        cardNames: [
            "Brass Man", "Dwarven Trader", "Goblins of the Flarg",
            "Ironclaw Orcs", "Brothers of Fire", "Orcish Artillery",
            "Dragon Whelp", "Orcish Cannoneers",
            "Lightning Bolt", "Incinerate", "Fireball", "Detonate", "Shatter",
            "Black Vise", "Zuran Orb", "Copper Tablet", "Immolation",
            "Dwarven Ruins", "Mishra's Factory", "Strip Mine", "Mountain",
        ]
    )

    static let necropotence = LandCategory(
        id: "inquest-necro",
        name: "Necropotence (Necro Summer)",
        iconName: "skull.fill",
        description: "The deck that dominated 'Necro Summer' 1996. Necropotence's 'pay 1 life, draw 1 card' engine was so broken it warped the entire format. Mono-black aggro-control with devastating discard.",
        cardNames: [
            "Necropotence", "Hymn to Tourach", "Hypnotic Specter",
            "Order of the Ebon Hand", "Knight of Stromgald",
            "Drain Life", "Dark Ritual", "Icequake", "Demonic Consultation",
            "Ivory Tower", "Zuran Orb", "Soul Burn",
            "Mishra's Factory", "Lake of the Dead", "Strip Mine", "Swamp",
        ]
    )

    static let turboStasis = LandCategory(
        id: "inquest-stasis",
        name: "Turbo Stasis",
        iconName: "lock.fill",
        description: "The ultimate prison deck (1997). Lock the game with Stasis, skip your own turn with Chronatog so you never need to pay the upkeep. Your opponent can never untap again.",
        cardNames: [
            "Stasis", "Howling Mine", "Boomerang", "Kismet",
            "Counterspell", "Force of Will", "Claws of Gix",
            "Feldon's Cane", "Birds of Paradise", "Chronatog", "Serra Angel",
            "Tropical Island", "Tundra", "Savannah", "Island",
        ]
    )

    static let erhnamgeddon = LandCategory(
        id: "inquest-erhnamgeddon",
        name: "Erhnamgeddon",
        iconName: "bolt.fill",
        description: "Green-white midrange (1996-1997). Deploy Erhnam Djinn and mana dorks, then Armageddon to strand your opponent with no lands while your creatures keep attacking. Brutally effective.",
        cardNames: [
            "Erhnam Djinn", "Birds of Paradise", "Llanowar Elves", "Serra Angel",
            "Swords to Plowshares", "Armageddon", "Disenchant", "Wrath of God",
            "Sylvan Library", "Regrowth", "Balance", "Land Tax", "Zuran Orb",
            "Fellwar Stone",
            "Savannah", "Brushland", "Mishra's Factory", "Strip Mine", "Forest", "Plains",
        ]
    )

    static let suicideBlack = LandCategory(
        id: "inquest-suicide-black",
        name: "Suicide Black",
        iconName: "heart.slash.fill",
        description: "Ultra-aggressive mono-black (1997-1998). Trade life for speed — Carnophage, Phyrexian Negator, and Hatred as a one-shot kill. 'Your life total is a resource.'",
        cardNames: [
            "Carnophage", "Dauthi Slayer", "Dauthi Horror", "Phyrexian Negator",
            "Flesh Reaver", "Sarcomancy", "Dark Ritual",
            "Hymn to Tourach", "Duress", "Unmask", "Snuff Out",
            "Wasteland", "Swamp",
        ]
    )

    static let landTaxScrollRack = LandCategory(
        id: "inquest-land-tax",
        name: "Land Tax / Scroll Rack",
        iconName: "books.vertical.fill",
        description: "The famous card-selection engine (1997-1998). Land Tax draws 3 basic lands, Scroll Rack swaps them for real cards. UW control with inevitability.",
        cardNames: [
            "Land Tax", "Scroll Rack", "Swords to Plowshares",
            "Enlightened Tutor", "Tithe", "Armageddon", "Wrath of God",
            "Moat", "Zuran Orb", "Ivory Tower", "Serra Angel",
            "Counterspell", "Force of Will", "Impulse", "Soldevi Digger",
            "Tundra", "Adarkar Wastes", "Flood Plain",
            "Library of Alexandria", "Plains", "Island",
        ]
    )

    static let firesOfYavimaya = LandCategory(
        id: "inquest-fires",
        name: "Fires of Yavimaya",
        iconName: "leaf.fill",
        description: "The definitive Invasion-era Standard deck (2000-2001). Fires of Yavimaya gives everything haste. Blastoderm and Saproling Burst provided unbeatable board presence.",
        cardNames: [
            "Llanowar Elves", "Birds of Paradise", "Blastoderm",
            "Jade Leech", "Shivan Wurm", "Flametongue Kavu",
            "Thornscape Battlemage", "Saproling Burst", "Fires of Yavimaya",
            "Ghitu Fire",
            "Rishadan Port", "Karplusan Forest", "City of Brass",
            "Dust Bowl", "Forest", "Mountain",
        ]
    )

    static let psychatog = LandCategory(
        id: "inquest-psychatog",
        name: "Psychatog",
        iconName: "brain.fill",
        description: "The dominant Odyssey Standard control deck (2001-2002). Psychatog was a 1/2 that could become 20/21 in an instant by eating your graveyard and hand. Upheaval + Psychatog was the kill.",
        cardNames: [
            "Psychatog", "Nightscape Familiar", "Fact or Fiction",
            "Counterspell", "Circular Logic", "Memory Lapse", "Upheaval",
            "Repulse", "Deep Analysis", "Chainer's Edict", "Aether Burst",
            "Salt Marsh", "Underground River", "Darkwater Catacombs",
            "Cephalid Coliseum", "Island", "Swamp",
        ]
    )

    static let ponza = LandCategory(
        id: "inquest-ponza",
        name: "Ponza (Red Land Destruction)",
        iconName: "hammer.fill",
        description: "Red land destruction and prison (1998-1999). Destroy every land your opponent plays while beating down with cheap creatures. A perennial InQuest favorite. Named after the Italian cheese — because it's 'cheesy.'",
        cardNames: [
            "Jackal Pup", "Mogg Fanatic", "Avalanche Riders",
            "Stone Rain", "Pillage", "Arc Lightning", "Shock",
            "Cursed Scroll",
            "Wasteland", "Dust Bowl", "Ghitu Encampment", "Rishadan Port", "Mountain",
        ]
    )
}
