import Foundation

/// Curated list of competitive Elder Dragon Highlander staples,
/// organized by role. Used by the "Lists" section alongside Lands.
/// Each category can be browsed with list/visual toggle and shows
/// owned quantities from the user's collection.
enum CEDHStaples {

    static let all: [LandCategory] = [
        fastMana,
        tutors,
        counterspells,
        cardDraw,
        removal,
        comboPieces,
        staxHate,
        cedhLands,
    ]

    static let fastMana = LandCategory(
        id: "cedh-fast-mana",
        name: "Fast Mana",
        iconName: "bolt.circle.fill",
        description: "Mana rocks, rituals, and dorks that accelerate your game plan by 1-3 turns. The backbone of every cEDH deck — getting your commander or combo out before opponents can answer.",
        cardNames: [
            "Sol Ring", "Mana Crypt", "Mox Diamond", "Chrome Mox",
            "Mox Opal", "Jeweled Lotus", "Lotus Petal", "Mana Vault",
            "Grim Monolith", "Arcane Signet", "Fellwar Stone",
            "Dark Ritual", "Cabal Ritual", "Rite of Flame",
            "Pyretic Ritual", "Desperate Ritual",
            "Birds of Paradise", "Deathrite Shaman",
            "Elvish Mystic", "Llanowar Elves", "Fyndhorn Elves",
            "Arbor Elf", "Elves of Deep Shadow",
            "Bloom Tender", "Dockside Extortionist",
            "Talisman of Dominance", "Talisman of Creativity",
        ]
    )

    static let tutors = LandCategory(
        id: "cedh-tutors",
        name: "Tutors",
        iconName: "magnifyingglass.circle.fill",
        description: "Search your library for exactly the card you need. In a singleton format, tutors are the most powerful consistency tool — they turn your 99-card deck into a toolbox.",
        cardNames: [
            "Demonic Tutor", "Vampiric Tutor", "Imperial Seal",
            "Mystical Tutor", "Enlightened Tutor", "Worldly Tutor",
            "Gamble", "Diabolic Intent", "Grim Tutor",
            "Wishclaw Talisman", "Muddle the Mixture",
            "Spellseeker", "Ranger-Captain of Eos",
            "Neoform", "Eldritch Evolution", "Finale of Devastation",
            "Green Sun's Zenith", "Chord of Calling",
            "Summoner's Pact", "Personal Tutor",
        ]
    )

    static let counterspells = LandCategory(
        id: "cedh-counters",
        name: "Counterspells",
        iconName: "hand.raised.circle.fill",
        description: "Protect your combo or stop opponents' winning plays. Free and low-cost counters dominate cEDH because you need to hold up interaction while deploying your own threats.",
        cardNames: [
            "Force of Will", "Force of Negation", "Pact of Negation",
            "Swan Song", "Mental Misstep", "Fierce Guardianship",
            "Deflecting Swat", "Flusterstorm", "Dispel",
            "Spell Pierce", "Negate", "Counterspell", "Mana Drain",
            "Dovin's Veto", "Delay", "An Offer You Can't Refuse",
            "Red Elemental Blast", "Pyroblast",
            "Silence", "Grand Abolisher",
            "Autumn's Veil", "Veil of Summer",
        ]
    )

    static let cardDraw = LandCategory(
        id: "cedh-draw",
        name: "Card Draw & Advantage",
        iconName: "book.circle.fill",
        description: "Draw more cards = see more answers and combo pieces. The best card-draw in cEDH is either free, massive, or persistent — Ad Nauseam and Necropotence can draw 20+ cards in one shot.",
        cardNames: [
            "Ad Nauseam", "Necropotence", "Rhystic Study",
            "Mystic Remora", "Sylvan Library", "Dark Confidant",
            "Tymna the Weaver", "Esper Sentinel",
            "Brainstorm", "Ponder", "Preordain", "Gitaxian Probe",
            "Windfall", "Wheel of Fortune", "Timetwister",
            "Treasure Cruise", "Dig Through Time",
            "Night's Whisper", "Sign in Blood",
            "Sensei's Divining Top", "Scroll Rack",
            "Jeska's Will", "Peer into the Abyss",
            "Faithless Looting", "Careful Study",
        ]
    )

    static let removal = LandCategory(
        id: "cedh-removal",
        name: "Removal",
        iconName: "xmark.circle.fill",
        description: "Efficient answers to opposing threats. cEDH removal must be cheap (1-2 mana max) or free — you can't afford to tap out for a 4-mana wrath when someone might combo off.",
        cardNames: [
            "Swords to Plowshares", "Path to Exile",
            "Chain of Vapor", "Cyclonic Rift",
            "Abrupt Decay", "Assassin's Trophy",
            "Nature's Claim", "Force of Vigor",
            "Toxic Deluge", "Fire Covenant", "Deadly Rollick",
            "Snuff Out", "Dismember", "Beast Within",
            "Generous Gift", "Rapid Hybridization", "Pongify",
            "Culling Ritual", "Vandalblast", "By Force",
            "Engineered Explosives", "Gilded Drake",
            "Oko, Thief of Crowns",
        ]
    )

    static let comboPieces = LandCategory(
        id: "cedh-combo",
        name: "Combo Pieces",
        iconName: "sparkles.rectangle.stack.fill",
        description: "Win conditions. Most cEDH games end via a 2-3 card combo. Thassa's Oracle + Demonic Consultation is the gold standard — 2 cards, 3 mana, instant win.",
        cardNames: [
            "Thassa's Oracle", "Demonic Consultation", "Tainted Pact",
            "Underworld Breach", "Brain Freeze",
            "Lion's Eye Diamond", "Yawgmoth's Will",
            "Isochron Scepter", "Dramatic Reversal",
            "Dualcaster Mage", "Twinflame",
            "Kiki-Jiki, Mirror Breaker", "Zealous Conscripts",
            "Walking Ballista", "Heliod, Sun-Crowned",
            "Food Chain", "Squee, the Immortal", "Eternal Scourge",
            "Animate Dead", "Birthing Pod", "Grinding Station",
            "Abdel Adrian, Gorion's Ward",
            "Splinter Twin", "Felidar Guardian", "Restoration Angel",
        ]
    )

    static let staxHate = LandCategory(
        id: "cedh-stax",
        name: "Stax & Hate Pieces",
        iconName: "lock.circle.fill",
        description: "Slow everyone down so your slower strategy can win. The best stax pieces are asymmetric — they hurt opponents more than you. Opposition Agent and Drannith Magistrate are format-defining.",
        cardNames: [
            "Rule of Law", "Deafening Silence",
            "Null Rod", "Collector Ouphe", "Stony Silence",
            "Cursed Totem", "Grafdigger's Cage",
            "Rest in Peace", "Opposition Agent",
            "Drannith Magistrate", "Aven Mindcensor",
            "Stranglehold", "Notion Thief",
            "Narset, Parter of Veils",
            "Spirit of the Labyrinth",
            "Thalia, Guardian of Thraben",
            "Lavinia, Azorius Renegade",
            "Blood Moon", "Back to Basics",
            "Torpor Orb", "Linvala, Keeper of Silence",
            "Containment Priest", "Blind Obedience",
        ]
    )

    static let cedhLands = LandCategory(
        id: "cedh-lands",
        name: "cEDH Lands",
        iconName: "mountain.2.circle.fill",
        description: "The mana base matters. cEDH decks run the best fixing (fetches + duals + shocks) plus utility lands that provide free value every turn.",
        cardNames: [
            "Command Tower", "Mana Confluence", "City of Brass",
            "Exotic Orchard", "Forbidden Orchard", "Ancient Tomb",
            "Gemstone Caverns", "Reflecting Pool",
            "Morphic Pool", "Luxury Suite", "Sea of Clouds",
            "Spire Garden", "Bountiful Promenade",
            "Urborg, Tomb of Yawgmoth", "Gaea's Cradle",
            "Mystic Sanctuary", "Boseiju, Who Endures",
            "Otawara, Soaring City", "Cavern of Souls",
            "Phyrexian Tower",
        ]
    )
}
