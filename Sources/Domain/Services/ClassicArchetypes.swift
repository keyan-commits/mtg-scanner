import Foundation

/// A historically significant decklist captured by hand from period sources
/// (PT coverage, magazines, MTG Wiki, TCDecks, etc.). Used by the
/// `ArchetypeMatcher` to recognize when a user is building a vintage/old-era
/// deck and offer accurate suggestions that MTGTop8 can't supply (because
/// MTGTop8 only has tournament data going back to ~2003).
///
/// Each list is "representative" — many of these decks had multiple variants.
/// The mainboard counts here reflect a common/canonical configuration.
struct ClassicArchetype: Identifiable, Sendable {
    let id: String
    let name: String
    let era: String
    let format: String
    let mainboard: [String: Int]
    /// Optional 15-card sideboard. Nil for archetypes where the canonical
    /// sideboard isn't well-documented.
    let sideboard: [String: Int]?
    let source: String
    let description: String

    init(
        id: String,
        name: String,
        era: String,
        format: String,
        mainboard: [String: Int],
        sideboard: [String: Int]? = nil,
        source: String,
        description: String
    ) {
        self.id = id
        self.name = name
        self.era = era
        self.format = format
        self.mainboard = mainboard
        self.sideboard = sideboard
        self.source = source
        self.description = description
    }

    var totalCards: Int {
        mainboard.values.reduce(0, +)
    }

    var sideboardCount: Int {
        sideboard?.values.reduce(0, +) ?? 0
    }
}

/// Static, hand-curated database of classic decks. Add archetypes here as
/// the user encounters new vintage decks.
enum ClassicArchetypes {

    static let all: [ClassicArchetype] = [
        // 1995-1996 Type II era
        necropotenceBlack1996,
        whiteWeenie1996,
        sligh1996,
        stasis1996,
        theDeck1995,
        highTide1996,
        // 1998-1999 Type II / Extended classics
        academy1998,
        trix1999,
        hatred1999,
        suicideBlack1999,
        replenish1999,
        // Premodern (1995-2003)
        goblinSlighPremodern,
        theRockPremodern,
        ugMadnessPremodern,
        astralSlidePremodern,
        // Standard format-definers
        affinityStandard2003,
        faeriesStandard2008,
        cawBladeStandard2011,
        monoBlackDevotionStandard2013,
        // Modern staples
        affinityModern,
        tronModern,
        jundModern,
        splinterTwinModern,
        deathsShadowModern,
        dredgeModern,
        // Legacy staples
        antStormLegacy,
        goblinsLegacy,
        deathAndTaxesLegacy,
        burnLegacy,
        reanimatorLegacy,
        survivalLegacy,
        poxLegacy,
        showAndTellLegacy,
        landsLegacy,
        maverickLegacy,
    ]

    // MARK: - 1995-1996 Type II era

    /// Famous "Necro Black" archetype that dominated late 1995 / early 1996
    /// Type II after Necropotence was printed in Ice Age. Mark Justice and
    /// many others played variants of this list.
    static let necropotenceBlack1996 = ClassicArchetype(
        id: "necro-black-1996",
        name: "Necropotence Black",
        era: "1996",
        format: "Type II",
        mainboard: [
            "Necropotence": 4,
            "Dark Ritual": 4,
            "Hymn to Tourach": 4,
            "Hypnotic Specter": 4,
            "Knight of Stromgald": 4,
            "Order of the Ebon Hand": 4,
            "Drain Life": 4,
            "Sinkhole": 4,
            "Contagion": 2,
            "Zuran Orb": 1,
            "Nevinyrral's Disk": 1,
            "Ivory Tower": 1,
            "Mishra's Factory": 4,
            "Strip Mine": 1,
            "Swamp": 18,
        ],
        source: "Type II metagame, Pro Tour New York 1996 era",
        description: "Black aggro-control built around Necropotence card draw, fast Hypnotic Specter / Knight of Stromgald beatdown, and Hymn to Tourach hand disruption."
    )

    /// "Tobias Henkel-style" White Weenie — the dominant aggressive white
    /// deck of late 1995 / 1996, post-Ice Age and Alliances.
    static let whiteWeenie1996 = ClassicArchetype(
        id: "white-weenie-1996",
        name: "White Weenie",
        era: "1996",
        format: "Type II",
        mainboard: [
            "Savannah Lions": 4,
            "White Knight": 4,
            "Order of Leitbur": 4,
            "Order of the White Shield": 4,
            "Crusade": 4,
            "Disenchant": 4,
            "Swords to Plowshares": 4,
            "Armageddon": 4,
            "Land Tax": 1,
            "Zuran Orb": 1,
            "Serrated Arrows": 2,
            "Kjeldoran Outpost": 4,
            "Mishra's Factory": 4,
            "Strip Mine": 1,
            "Plains": 15,
        ],
        source: "Type II metagame, post-Alliances",
        description: "Mono-white aggro using cheap protection-from-black creatures, Crusade pump, and Armageddon as a finisher. Kjeldoran Outpost provides recursive token pressure."
    )

    /// Mono-red Sligh — the original burn/aggro archetype refined by
    /// Paul Sligh and popularized at Pro Tour Atlanta 1996.
    static let sligh1996 = ClassicArchetype(
        id: "sligh-1996",
        name: "Sligh",
        era: "1996",
        format: "Type II",
        mainboard: [
            "Goblin Cadets": 4,
            "Mogg Fanatic": 4,
            "Ironclaw Orcs": 4,
            "Brothers of Fire": 4,
            "Orcish Artillery": 4,
            "Ball Lightning": 4,
            "Lightning Bolt": 4,
            "Incinerate": 4,
            "Fireblast": 4,
            "Stone Rain": 4,
            "Strip Mine": 1,
            "Mishra's Factory": 4,
            "Mountain": 15,
        ],
        source: "Paul Sligh, Pro Tour Atlanta 1996",
        description: "Mono-red curve-out aggro. The original 'one-drop, two-drop, three-drop, burn spell' template that defined aggressive deckbuilding for decades."
    )

    /// Howard Beasley-style Stasis lock from late 1995 Type II.
    static let stasis1996 = ClassicArchetype(
        id: "stasis-1996",
        name: "Stasis Lock",
        era: "1996",
        format: "Type II",
        mainboard: [
            "Stasis": 4,
            "Howling Mine": 4,
            "Counterspell": 4,
            "Power Sink": 4,
            "Force Spike": 4,
            "Boomerang": 4,
            "Brainstorm": 4,
            "Land Tax": 1,
            "Disenchant": 4,
            "Swords to Plowshares": 4,
            "Black Vise": 4,
            "Plains": 11,
            "Island": 8,
        ],
        source: "Type II metagame, late 1995",
        description: "Lock the opponent under Stasis + Howling Mine, then deal damage with Black Vise as their hand size grows. Counter their attempts to break the lock."
    )

    /// Brian Weissman's "The Deck" — the most famous Vintage / Type I
    /// control deck of the mid-1990s.
    static let theDeck1995 = ClassicArchetype(
        id: "the-deck-1995",
        name: "The Deck",
        era: "1995-1996",
        format: "Type I (Vintage)",
        mainboard: [
            "Ancestral Recall": 1,
            "Time Walk": 1,
            "Black Lotus": 1,
            "Mox Pearl": 1,
            "Mox Sapphire": 1,
            "Mox Jet": 1,
            "Mox Ruby": 1,
            "Mox Emerald": 1,
            "Sol Ring": 1,
            "Library of Alexandria": 1,
            "Mana Drain": 4,
            "Counterspell": 4,
            "Mana Vault": 4,
            "Mind Twist": 1,
            "Demonic Tutor": 1,
            "Disenchant": 4,
            "Swords to Plowshares": 4,
            "Wrath of God": 1,
            "Mirror Universe": 1,
            "Jayemdae Tome": 2,
            "Recall": 1,
            "Strip Mine": 4,
            "Underground Sea": 4,
            "Tundra": 4,
            "Volcanic Island": 1,
            "Plains": 1,
            "Island": 4,
        ],
        source: "Brian Weissman, Type I (Vintage), 1995-1996",
        description: "The original control deck. Restricts the opponent to one threat at a time, answers it, then wins with Mirror Universe + Library + card advantage."
    )

    // MARK: - Premodern era (1995-2003)

    /// Goblin Sligh — Onslaught-block goblin tribal aggression.
    static let goblinSlighPremodern = ClassicArchetype(
        id: "goblin-sligh-premodern",
        name: "Goblin Sligh",
        era: "Premodern",
        format: "Premodern",
        mainboard: [
            "Goblin Lackey": 4,
            "Mogg Fanatic": 4,
            "Goblin Piledriver": 4,
            "Goblin Warchief": 4,
            "Goblin Ringleader": 4,
            "Siege-Gang Commander": 3,
            "Goblin Matron": 4,
            "Skirk Prospector": 4,
            "Lightning Bolt": 4,
            "Wasteland": 4,
            "Rishadan Port": 4,
            "Mountain": 17,
        ],
        source: "Premodern metagame, post-Onslaught",
        description: "Goblin tribal aggression with Lackey → Piledriver / Ringleader chains. Siege-Gang as the finisher."
    )

    /// "The Rock" — Rock & Sock Robots, BG midrange built around
    /// Phyrexian Plaguelord, Spiritmonger, and discard.
    static let theRockPremodern = ClassicArchetype(
        id: "the-rock-premodern",
        name: "The Rock",
        era: "Premodern",
        format: "Premodern",
        mainboard: [
            "Birds of Paradise": 4,
            "Llanowar Elves": 4,
            "Spiritmonger": 4,
            "Phyrexian Plaguelord": 3,
            "Yavimaya Elder": 4,
            "Pernicious Deed": 4,
            "Duress": 4,
            "Cabal Therapy": 4,
            "Vampiric Tutor": 1,
            "Diabolic Edict": 2,
            "Treetop Village": 4,
            "Llanowar Wastes": 4,
            "Bayou": 4,
            "Forest": 8,
            "Swamp": 6,
        ],
        source: "Premodern metagame",
        description: "BG midrange with mana acceleration, hand disruption, and powerful midrange threats. Pernicious Deed handles aggro decks."
    )

    /// UG Madness — Wonder + Aquamoeba + Wild Mongrel madness shell.
    static let ugMadnessPremodern = ClassicArchetype(
        id: "ug-madness-premodern",
        name: "UG Madness",
        era: "Premodern",
        format: "Premodern",
        mainboard: [
            "Wild Mongrel": 4,
            "Aquamoeba": 4,
            "Arrogant Wurm": 4,
            "Roar of the Wurm": 4,
            "Basking Rootwalla": 4,
            "Wonder": 4,
            "Circular Logic": 4,
            "Daze": 4,
            "Counterspell": 4,
            "Brainstorm": 4,
            "Tropical Island": 4,
            "Flooded Strand": 4,
            "Forest": 6,
            "Island": 6,
        ],
        source: "Premodern metagame, Odyssey block",
        description: "Aggressive UG madness shell. Discard creatures to enable madness costs, attack with flying via Wonder."
    )

    // MARK: - 1998-1999 Type II / Extended classics

    /// Tolarian Academy combo — the deck that broke Urza's Saga and got
    /// half the format banned. Generated infinite mana via Academy +
    /// artifacts and won with Stroke of Genius / Mind Over Matter.
    static let academy1998 = ClassicArchetype(
        id: "academy-1998",
        name: "Tolarian Academy",
        era: "1998",
        format: "Type II / Extended",
        mainboard: [
            "Tolarian Academy": 4,
            "Mana Vault": 4,
            "Voltaic Key": 4,
            "Mind Over Matter": 4,
            "Stroke of Genius": 4,
            "Time Spiral": 4,
            "Windfall": 4,
            "Lotus Petal": 4,
            "Mox Diamond": 4,
            "Brainstorm": 4,
            "Counterspell": 4,
            "Power Sink": 4,
            "Force of Will": 4,
            "Sapphire Medallion": 4,
            "Island": 4,
        ],
        source: "Pro Tour Rome 1998 era",
        description: "Generates infinite mana via Tolarian Academy + Voltaic Key + Mana Vault, then wins by drawing the deck with Stroke of Genius. Got Academy + Tolarian Academy + Time Spiral + Windfall banned."
    )

    /// Trix — UB Necropotence + Donate + Illusions of Grandeur combo.
    /// Donate Illusions to the opponent, watch them lose 20 to upkeep.
    static let trix1999 = ClassicArchetype(
        id: "trix-1999",
        name: "Trix",
        era: "1999",
        format: "Extended",
        mainboard: [
            "Necropotence": 4,
            "Illusions of Grandeur": 4,
            "Donate": 4,
            "Force of Will": 4,
            "Counterspell": 4,
            "Daze": 4,
            "Brainstorm": 4,
            "Demonic Consultation": 4,
            "Duress": 4,
            "Dark Ritual": 4,
            "Mana Vault": 4,
            "Underground Sea": 4,
            "Polluted Delta": 4,
            "Island": 4,
            "Swamp": 4,
        ],
        source: "Extended metagame, 1999-2000",
        description: "Donate-the-bomb combo. Cast Illusions of Grandeur, gain 20 life, then Donate it to the opponent so they lose 20 to the cumulative upkeep. Necropotence draws the combo."
    )

    /// Hatred — 1999 Type II suicide black aggro-combo. Win by attacking
    /// with a Carnophage / Sarcomancy then casting Hatred for lethal.
    static let hatred1999 = ClassicArchetype(
        id: "hatred-1999",
        name: "Hatred (Suicide Black)",
        era: "1999",
        format: "Type II",
        mainboard: [
            "Carnophage": 4,
            "Dauthi Slayer": 4,
            "Sarcomancy": 4,
            "Skittering Skirge": 4,
            "Dauthi Horror": 4,
            "Hatred": 4,
            "Dark Ritual": 4,
            "Duress": 4,
            "Necropotence": 4,
            "Demonic Consultation": 1,
            "Hymn to Tourach": 4,
            "Swamp": 19,
        ],
        source: "Type II metagame, post-Tempest block",
        description: "Suicide Black aggro-combo. Trade life for tempo via Necropotence and pain creatures, then dump remaining life into Hatred for a lethal swing."
    )

    /// Pre-Hatred Suicide Black — slower, more grindy version with
    /// Bad Moon and more disruption.
    static let suicideBlack1999 = ClassicArchetype(
        id: "suicide-black-1999",
        name: "Suicide Black",
        era: "1999",
        format: "Type II",
        mainboard: [
            "Carnophage": 4,
            "Sarcomancy": 4,
            "Knight of Stromgald": 4,
            "Bad Moon": 4,
            "Hymn to Tourach": 4,
            "Duress": 4,
            "Dark Ritual": 4,
            "Necropotence": 4,
            "Diabolic Edict": 4,
            "Cursed Scroll": 4,
            "Wasteland": 4,
            "Strip Mine": 1,
            "Swamp": 15,
        ],
        source: "Type II metagame, late 1990s",
        description: "Mono-black aggro with hand disruption and Bad Moon-pumped early creatures. Cursed Scroll closes out the long game."
    )

    // MARK: - Legacy staples

    /// ANT — Ad Nauseam Tendrils. The defining storm combo deck of Legacy.
    static let antStormLegacy = ClassicArchetype(
        id: "ant-storm-legacy",
        name: "ANT (Ad Nauseam Tendrils)",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Brainstorm": 4,
            "Ponder": 4,
            "Preordain": 1,
            "Cabal Ritual": 4,
            "Dark Ritual": 4,
            "Lion's Eye Diamond": 4,
            "Lotus Petal": 4,
            "Duress": 4,
            "Thoughtseize": 2,
            "Ad Nauseam": 1,
            "Past in Flames": 1,
            "Infernal Tutor": 4,
            "Tendrils of Agony": 1,
            "Dark Petition": 1,
            "Polluted Delta": 4,
            "Bloodstained Mire": 4,
            "Underground Sea": 4,
            "Volcanic Island": 1,
            "Island": 2,
            "Swamp": 2,
        ],
        sideboard: [
            "Abrupt Decay": 3,
            "Defense Grid": 3,
            "Hope of Ghirapur": 2,
            "Massacre": 2,
            "Surgical Extraction": 2,
            "Chain of Vapor": 2,
            "Tropical Island": 1,
        ],
        source: "Legacy metagame",
        description: "Storm combo. Ritual into Ad Nauseam, draw the deck, chain spells, win with Tendrils of Agony for 20+ damage in a single turn."
    )

    /// Legacy Goblins — tribal aggro with Lackey + Vial chains.
    static let goblinsLegacy = ClassicArchetype(
        id: "goblins-legacy",
        name: "Goblins",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Goblin Lackey": 4,
            "Goblin Piledriver": 4,
            "Mogg War Marshal": 4,
            "Goblin Matron": 4,
            "Goblin Warchief": 4,
            "Goblin Ringleader": 4,
            "Stingscourger": 2,
            "Goblin Sharpshooter": 1,
            "Tuktuk Scrapper": 1,
            "Goblin Chieftain": 1,
            "Aether Vial": 4,
            "Wasteland": 4,
            "Rishadan Port": 4,
            "Cavern of Souls": 1,
            "Bloodstained Mire": 4,
            "Badlands": 1,
            "Mountain": 12,
            "Pendelhaven": 1,
        ],
        source: "Legacy metagame",
        description: "Tribal goblin aggro. Lackey into a 5-drop on turn 2, Vial in threats at instant speed, chain Ringleaders for card advantage."
    )

    /// Death & Taxes — mono-white prison/aggro built on disruption
    /// creatures and Stoneforge Mystic.
    static let deathAndTaxesLegacy = ClassicArchetype(
        id: "death-and-taxes-legacy",
        name: "Death & Taxes",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Mother of Runes": 4,
            "Stoneforge Mystic": 4,
            "Thalia, Guardian of Thraben": 4,
            "Flickerwisp": 4,
            "Phyrexian Revoker": 2,
            "Recruiter of the Guard": 2,
            "Brimaz, King of Oreskos": 1,
            "Aether Vial": 4,
            "Swords to Plowshares": 4,
            "Umezawa's Jitte": 1,
            "Sword of Fire and Ice": 1,
            "Batterskull": 1,
            "Wasteland": 4,
            "Rishadan Port": 4,
            "Karakas": 4,
            "Mishra's Factory": 4,
            "Plains": 12,
        ],
        sideboard: [
            "Containment Priest": 2,
            "Rest in Peace": 2,
            "Ethersworn Canonist": 2,
            "Council's Judgment": 2,
            "Cataclysm": 2,
            "Path to Exile": 2,
            "Pithing Needle": 2,
            "Disenchant": 1,
        ],
        source: "Legacy metagame",
        description: "Mono-white hatebears. Vial in disruption creatures (Thalia, Phyrexian Revoker), tutor Stoneforge equipment, lock the opponent under Wasteland + Port mana denial."
    )

    /// Legacy Burn — fast aggressive direct damage.
    static let burnLegacy = ClassicArchetype(
        id: "burn-legacy",
        name: "Burn",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Goblin Guide": 4,
            "Monastery Swiftspear": 4,
            "Eidolon of the Great Revel": 4,
            "Lightning Bolt": 4,
            "Chain Lightning": 4,
            "Lava Spike": 4,
            "Rift Bolt": 4,
            "Price of Progress": 4,
            "Fireblast": 4,
            "Sulfuric Vortex": 4,
            "Skullcrack": 3,
            "Wooded Foothills": 4,
            "Bloodstained Mire": 4,
            "Mountain": 9,
        ],
        sideboard: [
            "Smash to Smithereens": 3,
            "Searing Blood": 3,
            "Exquisite Firecraft": 2,
            "Pyroblast": 2,
            "Surgical Extraction": 2,
            "Path to Exile": 2,
            "Sulfur Elemental": 1,
        ],
        source: "Legacy metagame",
        description: "Mono-red burn. 12 creatures + 16 burn spells aim to deal 20 damage by turn 4. Price of Progress punishes greedy mana bases."
    )

    /// Legacy Reanimator — turn-1 Griselbrand via Entomb + Reanimate.
    static let reanimatorLegacy = ClassicArchetype(
        id: "reanimator-legacy",
        name: "Reanimator",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Entomb": 4,
            "Reanimate": 4,
            "Exhume": 4,
            "Animate Dead": 4,
            "Brainstorm": 4,
            "Ponder": 4,
            "Force of Will": 4,
            "Lotus Petal": 4,
            "Thoughtseize": 3,
            "Careful Study": 4,
            "Griselbrand": 1,
            "Iona, Shield of Emeria": 1,
            "Jin-Gitaxias, Core Augur": 1,
            "Underground Sea": 4,
            "Polluted Delta": 4,
            "Marsh Flats": 4,
            "Bayou": 1,
            "Bloodstained Mire": 1,
            "Swamp": 1,
            "Island": 3,
        ],
        source: "Legacy metagame",
        description: "Turn-1 Griselbrand via Entomb + Reanimate / Exhume. Draw 7 with Griselbrand's life-payment trigger, find protection, win the next turn."
    )

    /// Survival of the Fittest — tutor any creature into hand, then
    /// chain Vengevines and graveyard recursion.
    static let survivalLegacy = ClassicArchetype(
        id: "survival-legacy",
        name: "Survival",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Survival of the Fittest": 4,
            "Vengevine": 4,
            "Basking Rootwalla": 4,
            "Wild Mongrel": 4,
            "Genesis": 1,
            "Loyal Retainers": 1,
            "Iona, Shield of Emeria": 1,
            "Noble Hierarch": 4,
            "Birds of Paradise": 4,
            "Force of Will": 4,
            "Brainstorm": 4,
            "Daze": 4,
            "Tropical Island": 4,
            "Bayou": 1,
            "Misty Rainforest": 4,
            "Polluted Delta": 4,
            "Forest": 8,
        ],
        source: "Legacy metagame (banned 2011)",
        description: "Tutor 1-mana discard creatures (Rootwalla, Mongrel) to recur Vengevine for free. Survival itself was eventually banned for being too powerful."
    )

    /// Pox — mono-black symmetrical resource destruction. Force the
    /// opponent to sacrifice everything while you keep your own threats.
    static let poxLegacy = ClassicArchetype(
        id: "pox-legacy",
        name: "Pox",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Pox": 4,
            "Smallpox": 4,
            "Innocent Blood": 4,
            "Hymn to Tourach": 4,
            "Sinkhole": 4,
            "The Rack": 4,
            "Cursed Scroll": 2,
            "Wasteland": 4,
            "Mishra's Factory": 4,
            "Strip Mine": 1,
            "Dark Ritual": 4,
            "Liliana of the Veil": 4,
            "Swamp": 17,
        ],
        source: "Legacy metagame",
        description: "Mono-black symmetrical resource destruction. Pox + Smallpox + Innocent Blood force both players to sacrifice — but you have a leaner curve and inevitability via The Rack and creature lands."
    )

    /// Show and Tell / Sneak and Show — cheat a giant creature into play
    /// turn 2-3 via Show and Tell or Sneak Attack.
    static let showAndTellLegacy = ClassicArchetype(
        id: "sneak-show-legacy",
        name: "Sneak and Show",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Show and Tell": 4,
            "Sneak Attack": 4,
            "Emrakul, the Aeons Torn": 2,
            "Griselbrand": 2,
            "Force of Will": 4,
            "Spell Pierce": 2,
            "Brainstorm": 4,
            "Ponder": 4,
            "Preordain": 4,
            "Lotus Petal": 4,
            "Dig Through Time": 2,
            "Cunning Wish": 1,
            "Volcanic Island": 4,
            "Polluted Delta": 4,
            "Scalding Tarn": 4,
            "Flooded Strand": 4,
            "Island": 4,
            "Mountain": 1,
            "City of Traitors": 2,
        ],
        source: "Legacy metagame",
        description: "Cheat Emrakul or Griselbrand into play turn 2 via Show and Tell or Sneak Attack. Force of Will + counter suite protects the combo."
    )

    /// Lands — Legacy combo-control built around The Tabernacle at
    /// Pendrell Vale and Life from the Loam recursion.
    static let landsLegacy = ClassicArchetype(
        id: "lands-legacy",
        name: "Lands",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Life from the Loam": 4,
            "Crop Rotation": 4,
            "Exploration": 4,
            "Manabond": 2,
            "Punishing Fire": 4,
            "Mox Diamond": 4,
            "Sylvan Library": 2,
            "The Tabernacle at Pendrell Vale": 1,
            "Maze of Ith": 4,
            "Glacial Chasm": 2,
            "Wasteland": 4,
            "Rishadan Port": 4,
            "Grove of the Burnwillows": 4,
            "Tropical Island": 1,
            "Taiga": 1,
            "Bayou": 1,
            "Bojuka Bog": 1,
            "Forest": 4,
            "Karakas": 1,
            "Thespian's Stage": 4,
            "Dark Depths": 4,
        ],
        source: "Legacy metagame",
        description: "Lock down opponent threats via Tabernacle + Maze of Ith, recur lands with Life from the Loam, kill with Marit Lage from Dark Depths + Thespian's Stage."
    )

    /// Maverick — GW Knight of the Reliquary toolbox.
    static let maverickLegacy = ClassicArchetype(
        id: "maverick-legacy",
        name: "Maverick",
        era: "Legacy",
        format: "Legacy",
        mainboard: [
            "Knight of the Reliquary": 4,
            "Stoneforge Mystic": 3,
            "Mother of Runes": 4,
            "Noble Hierarch": 4,
            "Birds of Paradise": 1,
            "Qasali Pridemage": 4,
            "Scryb Ranger": 2,
            "Thalia, Guardian of Thraben": 3,
            "Gaddock Teeg": 1,
            "Green Sun's Zenith": 4,
            "Swords to Plowshares": 4,
            "Sylvan Library": 2,
            "Umezawa's Jitte": 1,
            "Batterskull": 1,
            "Wasteland": 4,
            "Karakas": 1,
            "Horizon Canopy": 4,
            "Windswept Heath": 4,
            "Savannah": 1,
            "Forest": 4,
            "Plains": 4,
        ],
        source: "Legacy metagame",
        description: "GW toolbox aggro. Green Sun's Zenith and Knight of the Reliquary tutor the right answer for any matchup. Stoneforge Mystic provides a finisher."
    )

    // MARK: - Additional 1990s era

    /// High Tide — UR storm combo from late Type II / Extended,
    /// pre-Urza's Saga.
    static let highTide1996 = ClassicArchetype(
        id: "high-tide-1996",
        name: "High Tide",
        era: "1996-1999",
        format: "Type II / Extended",
        mainboard: [
            "High Tide": 4,
            "Time Spiral": 4,
            "Meditate": 4,
            "Reset": 4,
            "Turnabout": 4,
            "Brainstorm": 4,
            "Counterspell": 4,
            "Force of Will": 4,
            "Impulse": 4,
            "Stroke of Genius": 2,
            "Mind Over Matter": 1,
            "Power Sink": 2,
            "Mana Leak": 2,
            "Island": 17,
        ],
        source: "Pro Tour Rome 1998 era",
        description: "Mono-blue storm combo. High Tide doubles Island mana, Time Spiral / Meditate refill the hand, Stroke of Genius mills the opponent."
    )

    /// Replenish — late-1999 combo deck using Replenish to bring back
    /// Opalescence + Parallax Wave for a one-shot kill.
    static let replenish1999 = ClassicArchetype(
        id: "replenish-1999",
        name: "Replenish",
        era: "1999-2000",
        format: "Type II",
        mainboard: [
            "Replenish": 4,
            "Opalescence": 4,
            "Parallax Wave": 4,
            "Parallax Tide": 4,
            "Frantic Search": 4,
            "Attunement": 4,
            "Counterspell": 4,
            "Force Spike": 4,
            "Brainstorm": 4,
            "Show and Tell": 2,
            "Thawing Glaciers": 2,
            "Tundra": 4,
            "Adarkar Wastes": 4,
            "Plains": 6,
            "Island": 6,
        ],
        source: "Pro Tour Chicago 2000 era",
        description: "Discard enchantments to the graveyard via Frantic Search + Attunement, then Replenish them all back into play. Opalescence turns Parallax Wave into a creature lock."
    )

    // MARK: - Premodern additions

    /// Astral Slide — UWR cycling-based control from Onslaught block.
    static let astralSlidePremodern = ClassicArchetype(
        id: "astral-slide-premodern",
        name: "Astral Slide",
        era: "Premodern",
        format: "Premodern",
        mainboard: [
            "Astral Slide": 4,
            "Lightning Rift": 4,
            "Renewed Faith": 4,
            "Akroma's Vengeance": 3,
            "Decree of Justice": 3,
            "Wrath of God": 2,
            "Exalted Angel": 3,
            "Eternal Dragon": 3,
            "Forgotten Cave": 4,
            "Secluded Steppe": 4,
            "Plateau": 2,
            "Mountain": 4,
            "Plains": 12,
            "Wooded Foothills": 4,
            "Bloodstained Mire": 4,
        ],
        source: "Premodern metagame, Onslaught block",
        description: "Cycle creatures into Astral Slide value, control the board with cyclable removal, win with Decree of Justice tokens or Eternal Dragon recursion."
    )

    // MARK: - Standard format-definers

    /// Standard Affinity — the deck that broke 2003-2004 Standard.
    /// Got Skullclamp + Disciple of the Vault + Arcbound Ravager
    /// banned and led to multiple sets being errata'd.
    static let affinityStandard2003 = ClassicArchetype(
        id: "affinity-standard-2003",
        name: "Affinity (Standard)",
        era: "2003-2004",
        format: "Standard",
        mainboard: [
            "Arcbound Ravager": 4,
            "Disciple of the Vault": 4,
            "Frogmite": 4,
            "Myr Enforcer": 4,
            "Atog": 4,
            "Cranial Plating": 4,
            "Skullclamp": 4,
            "Thoughtcast": 4,
            "Shrapnel Blast": 4,
            "Ornithopter": 4,
            "Welding Jar": 2,
            "Great Furnace": 4,
            "Seat of the Synod": 4,
            "Vault of Whispers": 4,
            "Glimmervoid": 4,
            "Blinkmoth Nexus": 2,
        ],
        source: "Mirrodin block Standard, 2003-2004",
        description: "Free-spell artifact aggro. Affinity reduces costs to nothing, Arcbound Ravager + Disciple of the Vault closes games. Multiple cards eventually banned."
    )

    /// Faeries — Standard 2008-2009. Bitterblossom + Mistbind Clique
    /// tempo control that dominated for two years.
    static let faeriesStandard2008 = ClassicArchetype(
        id: "faeries-standard-2008",
        name: "Faeries",
        era: "2008-2009",
        format: "Standard",
        mainboard: [
            "Bitterblossom": 4,
            "Mistbind Clique": 4,
            "Spellstutter Sprite": 4,
            "Scion of Oona": 3,
            "Cryptic Command": 4,
            "Broken Ambitions": 4,
            "Thoughtseize": 4,
            "Agony Warp": 2,
            "Sower of Temptation": 2,
            "Vendilion Clique": 2,
            "Mutavault": 4,
            "Underground River": 4,
            "Sunken Ruins": 4,
            "Secluded Glen": 4,
            "Island": 6,
            "Swamp": 5,
        ],
        source: "Lorwyn-Shadowmoor Standard, 2008-2009",
        description: "UB Faerie tribal tempo control. Bitterblossom for free attackers, Mistbind Clique to lock the opponent's main phase, Cryptic Command for everything else."
    )

    /// Caw-Blade — Stoneforge Mystic + Squadron Hawk + Jace, the Mind
    /// Sculptor. Banned 2 cards from the deck after one season.
    static let cawBladeStandard2011 = ClassicArchetype(
        id: "caw-blade-standard-2011",
        name: "Caw-Blade",
        era: "2011",
        format: "Standard",
        mainboard: [
            "Stoneforge Mystic": 4,
            "Squadron Hawk": 4,
            "Jace, the Mind Sculptor": 4,
            "Gideon Jura": 2,
            "Mortarpod": 1,
            "Sword of Feast and Famine": 2,
            "Sword of War and Peace": 1,
            "Batterskull": 1,
            "Day of Judgment": 2,
            "Mana Leak": 4,
            "Spell Pierce": 2,
            "Preordain": 4,
            "Into the Roil": 1,
            "Tectonic Edge": 4,
            "Celestial Colonnade": 4,
            "Glacial Fortress": 4,
            "Seachrome Coast": 4,
            "Island": 7,
            "Plains": 5,
        ],
        source: "Mirrodin Besieged Standard, 2011",
        description: "Stoneforge Mystic tutors equipment, Squadron Hawk fetches more Hawks, Jace controls the game. Stoneforge + Jace banned within one season."
    )

    /// Mono-Black Devotion — the Pack Rat / Gray Merchant deck that
    /// dominated 2013-2014 Standard.
    static let monoBlackDevotionStandard2013 = ClassicArchetype(
        id: "mono-black-devotion-2013",
        name: "Mono-Black Devotion",
        era: "2013-2014",
        format: "Standard",
        mainboard: [
            "Pack Rat": 4,
            "Nightveil Specter": 4,
            "Desecration Demon": 4,
            "Gray Merchant of Asphodel": 4,
            "Lifebane Zombie": 3,
            "Hero's Downfall": 4,
            "Devour Flesh": 3,
            "Bile Blight": 2,
            "Thoughtseize": 4,
            "Underworld Connections": 3,
            "Erebos, God of the Dead": 1,
            "Mutavault": 4,
            "Swamp": 20,
        ],
        source: "Theros Standard, 2013-2014",
        description: "Mono-black devotion grindfest. Pack Rat snowballs, Underworld Connections draws cards, Gray Merchant drains for lethal."
    )

    // MARK: - Modern staples

    /// Modern Affinity / Robots — descendant of the 2003 Standard deck,
    /// shifted into Modern after the bannings ironically didn't kill it.
    static let affinityModern = ClassicArchetype(
        id: "affinity-modern",
        name: "Affinity (Robots)",
        era: "Modern",
        format: "Modern",
        mainboard: [
            "Arcbound Ravager": 4,
            "Steel Overseer": 4,
            "Signal Pest": 4,
            "Vault Skirge": 4,
            "Memnite": 4,
            "Ornithopter": 4,
            "Cranial Plating": 4,
            "Galvanic Blast": 4,
            "Mox Opal": 4,
            "Springleaf Drum": 4,
            "Welding Jar": 2,
            "Darksteel Citadel": 4,
            "Inkmoth Nexus": 4,
            "Blinkmoth Nexus": 4,
            "Glimmervoid": 4,
            "Spire of Industry": 2,
        ],
        sideboard: [
            "Etched Champion": 3,
            "Ancient Grudge": 3,
            "Thoughtseize": 2,
            "Spell Pierce": 2,
            "Whipflare": 2,
            "Grafdigger's Cage": 2,
            "Dispatch": 1,
        ],
        source: "Modern metagame",
        description: "Free artifact aggro. Mox Opal enables explosive turn-1 starts, Arcbound Ravager + Inkmoth Nexus poisons out the opponent in 2 attacks."
    )

    /// Mono-Green Tron — the seven-mana-on-turn-three deck.
    static let tronModern = ClassicArchetype(
        id: "tron-modern",
        name: "Mono-Green Tron",
        era: "Modern",
        format: "Modern",
        mainboard: [
            "Urza's Mine": 4,
            "Urza's Power Plant": 4,
            "Urza's Tower": 4,
            "Sylvan Scrying": 4,
            "Ancient Stirrings": 4,
            "Expedition Map": 4,
            "Chromatic Sphere": 4,
            "Chromatic Star": 4,
            "Pyroclasm": 3,
            "Relic of Progenitus": 3,
            "Karn Liberated": 2,
            "Wurmcoil Engine": 2,
            "Ugin, the Spirit Dragon": 1,
            "Oblivion Stone": 4,
            "Forest": 4,
            "Ghost Quarter": 4,
            "Sanctum of Ugin": 1,
        ],
        source: "Modern metagame",
        description: "Assemble Urza's Mine + Power Plant + Tower for 7 colorless mana, then cast Karn / Ugin / Wurmcoil Engine on turn 3."
    )

    /// Jund — BGR midrange, the format-warping fair deck of early Modern.
    static let jundModern = ClassicArchetype(
        id: "jund-modern",
        name: "Jund",
        era: "Modern",
        format: "Modern",
        mainboard: [
            "Tarmogoyf": 4,
            "Dark Confidant": 4,
            "Bloodbraid Elf": 4,
            "Liliana of the Veil": 4,
            "Lightning Bolt": 4,
            "Inquisition of Kozilek": 4,
            "Thoughtseize": 3,
            "Abrupt Decay": 3,
            "Terminate": 2,
            "Maelstrom Pulse": 1,
            "Kolaghan's Command": 1,
            "Scavenging Ooze": 2,
            "Verdant Catacombs": 4,
            "Wooded Foothills": 4,
            "Bloodstained Mire": 4,
            "Overgrown Tomb": 1,
            "Stomping Ground": 1,
            "Blood Crypt": 1,
            "Forest": 1,
            "Swamp": 1,
            "Mountain": 1,
            "Raging Ravine": 2,
        ],
        source: "Modern metagame",
        description: "BGR midrange. Tarmogoyf + Dark Confidant for value, Liliana for control, Bloodbraid Elf for tempo. The 'fair Magic' answer to combo decks."
    )

    /// Splinter Twin — UR combo using Splinter Twin on Deceiver Exarch
    /// for infinite hasty creatures.
    static let splinterTwinModern = ClassicArchetype(
        id: "splinter-twin-modern",
        name: "Splinter Twin",
        era: "Modern",
        format: "Modern",
        mainboard: [
            "Splinter Twin": 4,
            "Deceiver Exarch": 4,
            "Pestermite": 3,
            "Snapcaster Mage": 3,
            "Lightning Bolt": 4,
            "Serum Visions": 4,
            "Sleight of Hand": 3,
            "Remand": 4,
            "Cryptic Command": 2,
            "Spell Snare": 2,
            "Dispel": 2,
            "Electrolyze": 1,
            "Steam Vents": 2,
            "Scalding Tarn": 4,
            "Misty Rainforest": 1,
            "Sulfur Falls": 4,
            "Island": 6,
            "Mountain": 3,
        ],
        source: "Modern metagame (banned 2016)",
        description: "Twin on Deceiver Exarch / Pestermite makes infinite hasty creatures. Lightning Bolt + counter suite buys time. Banned for being too consistent."
    )

    /// Death's Shadow — Modern aggro that uses life total as a resource.
    static let deathsShadowModern = ClassicArchetype(
        id: "deaths-shadow-modern",
        name: "Death's Shadow",
        era: "Modern",
        format: "Modern",
        mainboard: [
            "Death's Shadow": 4,
            "Street Wraith": 4,
            "Tarmogoyf": 4,
            "Snapcaster Mage": 1,
            "Inquisition of Kozilek": 4,
            "Thoughtseize": 4,
            "Stubborn Denial": 4,
            "Fatal Push": 4,
            "Kolaghan's Command": 1,
            "Temur Battle Rage": 2,
            "Mishra's Bauble": 4,
            "Lightning Bolt": 1,
            "Verdant Catacombs": 4,
            "Bloodstained Mire": 4,
            "Polluted Delta": 2,
            "Watery Grave": 1,
            "Overgrown Tomb": 1,
            "Stomping Ground": 1,
            "Bayou": 1,
            "Swamp": 1,
            "Forest": 1,
            "Wooded Foothills": 2,
        ],
        source: "Modern metagame",
        description: "Use Thoughtseize, Street Wraith, and fetch lands to drop your life to 1, then cast a 13/13 Death's Shadow for one mana. Temur Battle Rage closes the game."
    )

    /// Modern Dredge — Cathartic Reunion + Faithless Looting + Prized
    /// Amalgam graveyard recursion.
    static let dredgeModern = ClassicArchetype(
        id: "dredge-modern",
        name: "Dredge",
        era: "Modern",
        format: "Modern",
        mainboard: [
            "Stinkweed Imp": 4,
            "Golgari Grave-Troll": 1,
            "Golgari Thug": 4,
            "Prized Amalgam": 4,
            "Bloodghast": 4,
            "Narcomoeba": 4,
            "Conflagrate": 3,
            "Life from the Loam": 3,
            "Cathartic Reunion": 4,
            "Faithless Looting": 4,
            "Insolent Neonate": 4,
            "Creeping Chill": 4,
            "Bloodstained Mire": 2,
            "Wooded Foothills": 1,
            "Mountain": 2,
            "Stomping Ground": 1,
            "Copperline Gorge": 1,
            "Blood Crypt": 1,
            "Mana Confluence": 1,
            "Gemstone Mine": 4,
            "Swamp": 2,
            "Forest": 2,
        ],
        source: "Modern metagame",
        description: "Discard a Dredge card, return it to mill the deck, fill graveyard with creatures, attack with recurring Bloodghast / Prized Amalgam / Narcomoeba."
    )
}
