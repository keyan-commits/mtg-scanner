import Foundation

// MARK: - Major Archetype

/// A curated "umbrella" archetype that groups together multiple
/// related MTGTop8 deck names (e.g. "Affinity (Robots)", "UW
/// Affinity", "Mono-Blue Affinity" all roll up under "Affinity").
///
/// These power the new Browse Archetypes screen — a hand-picked list
/// of the most iconic decks in MTG history, each with its own page
/// (intro, strategy, common cards live-aggregated from MTGTop8 data
/// across all matching variants).
///
/// `matchTerms` are case-insensitive substrings used to find related
/// archetypes in `MTGTop8ArchetypeIndex`. Keep them broad enough to
/// catch every variant but narrow enough to avoid false positives.
struct MajorArchetype: Identifiable, Sendable {
    let id: String
    let name: String
    /// SF Symbol icon shown on the browse grid + detail header.
    let iconName: String
    /// Theme tint hex string (e.g. "#E74C3C"). Resolved at view time.
    let tintHex: String
    /// 2-3 sentence elevator pitch — what the deck IS at a glance.
    let intro: String
    /// "How to play" — typically 2-4 short paragraphs covering the
    /// game plan, key interactions, and common decision points.
    let strategy: String
    /// Substrings used to find matching MTGTop8 archetype names.
    /// Case-insensitive substring match.
    let matchTerms: [String]
    /// Hand-picked signature cards. Used as a fallback if the live
    /// aggregator returns nothing (e.g., on first paint while the
    /// network call is in flight, or when MTGTop8 has no recent data).
    let signatureCards: [String]
}

// MARK: - Catalog

/// Static catalog of hand-curated major archetypes. These get rich
/// detail pages with full intro + strategy text. Every OTHER archetype
/// the user encounters via `ArchetypeGroup` falls back to placeholder
/// content but still gets its own browseable page (with the variants
/// list and live-aggregated common cards).
///
/// To add a curated entry: write the struct, append to `all`, and
/// make sure its `id` matches the canonical name produced by
/// `ArchetypeGrouper.canonicalName(from:)` for the variants you
/// want it to attach to.
enum MajorArchetypes {

    static let all: [MajorArchetype] = [
        burn,
        affinity,
        tron,
        storm,
        heroic,
        deathsShadow,
        deathAndTaxes,
        lands,
        reanimator,
        eldrazi,
        goblins,
        slivers,
        sneakAndShow,
    ]

    /// Returns the curated entry whose `id` (or any of its
    /// `matchTerms`) matches the given canonical name. Used by
    /// `ArchetypeGroup` to enrich an auto-grouped archetype with
    /// hand-written content AND to alias different MTGTop8 names
    /// (e.g. "Red Deck Wins" → Burn) into a single bucket.
    ///
    /// Match rules (in order):
    /// 1. Exact match against `id`, `name.lowercased()`, or any
    ///    `matchTerm.lowercased()`
    /// 2. Word-boundary match: any single-word matchTerm appearing
    ///    as a whole word inside the canonical name
    ///
    /// Word-boundary matching avoids "burning tree" → Burn false
    /// positives while still merging "Boros Burn" → "burn" → Burn.
    static func curatedFor(canonicalName: String) -> MajorArchetype? {
        let lowered = canonicalName.lowercased()
        let words = Set(lowered.split(separator: " ").map(String.init))
        return all.first { major in
            if major.id == lowered { return true }
            if major.name.lowercased() == lowered { return true }
            return major.matchTerms.contains { term in
                let lowerTerm = term.lowercased()
                if lowerTerm == lowered { return true }
                // Single-word term: must appear as a whole word in canonical
                if !lowerTerm.contains(" ") {
                    return words.contains(lowerTerm)
                }
                return false
            }
        }
    }

    // MARK: - Aggro

    static let burn = MajorArchetype(
        id: "burn",
        name: "Burn",
        iconName: "flame.fill",
        tintHex: "#E74C3C",
        intro: "Burn is the most direct strategy in Magic: deal 20 damage to your opponent's face as fast as possible using cheap, efficient damage spells. No subtlety, no card advantage — just race the clock.",
        strategy: """
        Your game plan is simple: every card in your deck should reduce your opponent's life total. Lightning Bolt, Lava Spike, Rift Bolt, and Skewer the Critics each deal 3 for one mana. Eidolon of the Great Revel and Goblin Guide pressure them every turn. Searing Blaze and Lightning Helix gain you tempo by killing creatures while still pushing damage.

        Play creatures on turn 1, burn spells on turns 2-4, and finish with Boros Charm or Skewer for the kill. Mulligan aggressively for hands that can deal 12+ damage in 4 turns.

        The hardest decision is whether to point a burn spell at a creature or face. Rule of thumb: face damage wins games, creature kills only matter if their creature would deal more than 2 damage back. Save your reach (Skewer the Critics) for the kill turn.
        """,
        matchTerms: ["burn", "red deck wins", "rdw", "mono red", "sligh"],
        signatureCards: [
            "Lightning Bolt",
            "Lava Spike",
            "Rift Bolt",
            "Goblin Guide",
            "Eidolon of the Great Revel",
            "Boros Charm",
            "Skewer the Critics",
            "Searing Blaze",
            "Lightning Helix",
            "Monastery Swiftspear",
        ]
    )

    static let affinity = MajorArchetype(
        id: "affinity",
        name: "Affinity",
        iconName: "gearshape.2.fill",
        tintHex: "#5DADE2",
        intro: "Affinity (also called Robots) is the most explosive artifact deck in Magic. By flooding the board with 0-cost artifacts, your spells become free, and a turn-3 lethal is the baseline expectation.",
        strategy: """
        The deck is built around the Affinity for Artifacts mechanic — each artifact you control reduces the cost of certain spells by one. Open with Mox Opal or a fast-mana enabler, drop Memnite, Ornithopter, and Springleaf Drum on turn 1, then cast Cranial Plating equipped to a flier for 8+ damage on turn 3.

        Arcbound Ravager turns your board into a one-shot kill — sacrifice everything to put +1/+1 counters on a Plated Ornithopter, then equip and swing for lethal. Steel Overseer pumps your team every turn it survives.

        The main weakness is artifact hate (Stony Silence, Shatterstorm). Sideboard plans typically pivot to a more creature-heavy plan with Etched Champion or shift colors entirely. Always have a backup threat for game 2.
        """,
        matchTerms: ["affinity", "robots"],
        signatureCards: [
            "Cranial Plating",
            "Arcbound Ravager",
            "Steel Overseer",
            "Memnite",
            "Ornithopter",
            "Springleaf Drum",
            "Mox Opal",
            "Vault Skirge",
            "Inkmoth Nexus",
            "Blinkmoth Nexus",
        ]
    )

    static let goblins = MajorArchetype(
        id: "goblins",
        name: "Goblins",
        iconName: "person.3.fill",
        tintHex: "#D35400",
        intro: "Goblins is Magic's longest-running tribal aggro deck. Cheap creatures, swarm tactics, and powerful tribal lords combine into a snowballing red menace that's been winning tournaments since 1996.",
        strategy: """
        Goblin Lackey on turn 1 is the dream — every connecting Lackey lets you cheat a Goblin Piledriver, Goblin Warchief, or Krenko, Mob Boss into play for free. Goblin Matron tutors for whichever piece you need most: Goblin Ringleader for card advantage, Siege-Gang Commander for reach, or a hate creature like Goblin Trashmaster.

        Aether Vial is the engine that makes the deck busted in older formats — it lets you flash in creatures at instant speed, dodging counterspells and triggering combat tricks. Goblin Warchief gives the entire team haste and reduces costs.

        The biggest decision tree is how aggressively to commit to the board vs. play around sweepers. Against control, play one or two Goblins per turn and hold up Aether Vial. Against creature decks, flood the board and out-tempo them with Piledriver swings.
        """,
        matchTerms: ["goblin"],
        signatureCards: [
            "Goblin Lackey",
            "Goblin Piledriver",
            "Goblin Warchief",
            "Goblin Matron",
            "Goblin Ringleader",
            "Krenko, Mob Boss",
            "Aether Vial",
            "Siege-Gang Commander",
            "Mogg War Marshal",
            "Munitions Expert",
        ]
    )

    static let heroic = MajorArchetype(
        id: "heroic",
        name: "Heroic",
        iconName: "shield.lefthalf.filled",
        tintHex: "#F39C12",
        intro: "Heroic builds one massive creature out of cheap white aura threats. By stacking pump effects and protection spells on a single Heroic-mechanic creature, you can swing for lethal as early as turn 3.",
        strategy: """
        The core engine is a creature with the Heroic ability (Favored Hoplite, Akroan Crusader, Hero of Iroas, Lagonna-Band Trailblazer) that triggers whenever you target it with a spell. Each Aura you cast on it pumps it AND triggers Heroic — a one-mana Aura becomes a +2/+2 effective swing.

        Eidolon of Countless Battles scales with your other auras and creatures, often becoming a 6/6 or larger for two mana. Ethereal Armor gives first strike and grows with every enchantment.

        Always protect your one big threat. Karametra's Blessing and Apostle's Blessing make your Hoplite indestructible AND trigger Heroic for an extra +1/+1. Holding up protection is more important than playing more auras — one removal spell ruins the entire game.

        Mulligan rule: keep any hand with a one-drop Heroic creature and an Ethereal Armor or Aura on turn 2.
        """,
        matchTerms: ["heroic"],
        signatureCards: [
            "Favored Hoplite",
            "Akroan Crusader",
            "Hero of Iroas",
            "Eidolon of Countless Battles",
            "Ethereal Armor",
            "Karametra's Blessing",
            "Lagonna-Band Trailblazer",
            "Daxos, Blessed by the Sun",
            "All That Glitters",
            "Gods Willing",
        ]
    )

    static let deathAndTaxes = MajorArchetype(
        id: "death-and-taxes",
        name: "Death and Taxes",
        iconName: "scalemass.fill",
        tintHex: "#ECF0F1",
        intro: "Death and Taxes is white weenie with a twist: instead of just attacking, you tax your opponent's mana and lock down their lands while pressuring with cheap creatures. The deck punishes greedy mana bases and slow strategies.",
        strategy: """
        The lock pieces are non-creature taxers — Thalia, Guardian of Thraben (all noncreature spells cost 1 more), Aether Vial (flash in creatures around counterspells), and Wasteland or Rishadan Port (kill or tap their mana every turn).

        Stoneforge Mystic into Batterskull or Kaldra Compleat is the win condition. Phyrexian Revoker shuts down a key planeswalker or activated ability. Mother of Runes protects your stuff with constant protection-from-color shields.

        The deck plays at instant speed thanks to Aether Vial. Always hold up Vial activations, Wasteland, and Mom protection. The trick is sequencing — play Thalia BEFORE casting other spells so they don't get the +1 tax.

        Against combo, race with Wasteland + Thalia. Against control, leverage Aether Vial to dodge counterspells. Against creature decks, lean on Stoneforge equipment and Mother of Runes.
        """,
        matchTerms: ["death and taxes", "death & taxes", "d&t", "white weenie"],
        signatureCards: [
            "Thalia, Guardian of Thraben",
            "Stoneforge Mystic",
            "Mother of Runes",
            "Aether Vial",
            "Wasteland",
            "Rishadan Port",
            "Phyrexian Revoker",
            "Batterskull",
            "Flickerwisp",
            "Karakas",
        ]
    )

    // MARK: - Midrange

    static let deathsShadow = MajorArchetype(
        id: "deaths-shadow",
        name: "Death's Shadow",
        iconName: "person.crop.circle.badge.exclamationmark.fill",
        tintHex: "#7D3C98",
        intro: "Death's Shadow turns your own life total into a weapon. By dropping yourself to 5 or below, your one-mana 13/13 attacker comes online, backed by hand disruption and the most efficient removal in the format.",
        strategy: """
        Step one: hurt yourself. Thoughtseize, Dismember, fetchlands, and shocklands are all life-payment effects that fuel Death's Shadow's growth. The threshold to start is 13 life — at that point, Shadow is 1/1; at 5 life it's 8/8; at 1 life it's a 12/12 for one mana.

        The deck is essentially an aggro-control hybrid. You disrupt their key plays with Thoughtseize and Inquisition of Kozilek, kill threats with Fatal Push and Lightning Bolt, then close with Death's Shadow + Temur Battle Rage for one-shot kills.

        The hardest skill is life-total management. You need to be low enough that Shadow is huge but high enough that you can survive their next attack. Stubborn Denial counters their key removal — but it requires "ferocious" (a creature with power 4+) which Shadow naturally enables.

        Snapcaster Mage flashbacks your disruption and burn for double value. Always keep counts of cards in hand and cards in opponent's graveyard for Tarmogoyf math.
        """,
        matchTerms: ["death's shadow", "deaths shadow", "shadow"],
        signatureCards: [
            "Death's Shadow",
            "Thoughtseize",
            "Inquisition of Kozilek",
            "Fatal Push",
            "Stubborn Denial",
            "Temur Battle Rage",
            "Street Wraith",
            "Mishra's Bauble",
            "Snapcaster Mage",
            "Tarmogoyf",
        ]
    )

    // MARK: - Combo / Ramp

    static let tron = MajorArchetype(
        id: "tron",
        name: "Tron",
        iconName: "cube.transparent.fill",
        tintHex: "#27AE60",
        intro: "Tron assembles three specific lands — Urza's Mine, Urza's Power Plant, and Urza's Tower — to generate seven mana on turn 3. From there, you cast game-ending threats turns ahead of any normal deck.",
        strategy: """
        The opening is all about finding Tron pieces. Sylvan Scrying, Ancient Stirrings, Expedition Map, and Chromatic Sphere/Star dig through your deck for the missing land. A turn-3 Tron means turn-3 Karn Liberated, Wurmcoil Engine, or Ulamu, the Ceaseless Hunger — game-warping threats that win in 1-2 turns.

        Your deck does NOT have a turn 1 or 2 play besides cantrips and ramp. You concede early board pressure to set up the explosive turn 3. Oblivion Stone resets the board if they get ahead. Karn Liberated exiles permanents AND restarts the game from a winning position.

        Against fast aggro, you race with Wurmcoil Engine (lifelink saves you) and Walking Ballista (sweeps go-wide boards). Against control, you flood with planeswalkers and force them to use answers.

        The most common mistake: trying to find Tron pieces too aggressively. Ancient Stirrings and Sylvan Scrying find them when you NEED them — burning multiple cantrips on turn 1 wastes resources you'll need later.
        """,
        matchTerms: ["tron"],
        signatureCards: [
            "Urza's Tower",
            "Urza's Mine",
            "Urza's Power Plant",
            "Karn Liberated",
            "Wurmcoil Engine",
            "Sylvan Scrying",
            "Ancient Stirrings",
            "Expedition Map",
            "Chromatic Sphere",
            "Oblivion Stone",
            "Ugin, the Spirit Dragon",
            "Walking Ballista",
        ]
    )

    static let storm = MajorArchetype(
        id: "storm",
        name: "Storm",
        iconName: "tornado",
        tintHex: "#9B59B6",
        intro: "Storm chains together cheap spells and rituals to build up the Storm count, then casts a single payoff that copies for every spell cast that turn. A turn-3 kill from a 0% board state is the deck's signature.",
        strategy: """
        The core combo is rituals + Storm payoffs. Dark Ritual produces three black mana from one. Cabal Ritual ramps further. Lotus Petal is a free mana boost. After a few rituals you cast Tendrils of Agony or Grapeshot — Tendrils with Storm 7 deals 16 damage AND drains for 16 life.

        The setup is cantrips: Brainstorm, Ponder, Preordain, and Gitaxian Probe see deep into your deck and find the right combinations. Past in Flames flashbacks all your spells from the graveyard, doubling your Storm count.

        Always count carefully: every spell cast THIS TURN counts toward Storm. Cast cantrips first to fix your hand, then rituals to ramp, then the payoff. Practice the math before going off — a botched Storm turn ends the game in your opponent's favor.

        Against counterspells, Defense Grid and Pact of Negation force your kill through. Against discard, you race them — go off before they strip your hand.
        """,
        matchTerms: ["storm", "ant", "tendrils", "ad nauseam tendrils", "the epic storm", "tes"],
        signatureCards: [
            "Tendrils of Agony",
            "Dark Ritual",
            "Cabal Ritual",
            "Lotus Petal",
            "Brainstorm",
            "Ponder",
            "Past in Flames",
            "Gitaxian Probe",
            "Lion's Eye Diamond",
            "Ad Nauseam",
            "Duress",
            "Infernal Tutor",
        ]
    )

    static let reanimator = MajorArchetype(
        id: "reanimator",
        name: "Reanimator",
        iconName: "arrow.up.heart.fill",
        tintHex: "#1B4F72",
        intro: "Reanimator cheats giant creatures into play on turn 1. Discard a Griselbrand to your graveyard with Entomb or Faithless Looting, then Reanimate or Exhume it back to the battlefield for two mana.",
        strategy: """
        The deck has two halves: enablers and threats. Enablers (Entomb, Faithless Looting, Putrid Imp, Careful Study) put a fatty in the graveyard on turn 1. Threats (Griselbrand, Iona, Shield of Emeria, Jin-Gitaxias, Core Augur, Archon of Cruelty, Atraxa) come back via Reanimate or Exhume.

        The dream opener: turn 1 Entomb (find Griselbrand) + Reanimate. You're now at 18 life with a 7/7 lifelinker that draws 7 cards on attack. From there you draw into more disruption, more reanimation, and the game is yours.

        Force of Will and Daze protect your combo. Thoughtseize strips their answers. Show and Tell is an alternate way to put Griselbrand into play if your graveyard plan is disrupted.

        Against graveyard hate (Leyline of the Void, Surgical Extraction), pivot to Show and Tell or hard-cast a smaller threat. Always know your fail-state plan before going off.
        """,
        matchTerms: ["reanimator", "reanimate"],
        signatureCards: [
            "Entomb",
            "Reanimate",
            "Exhume",
            "Griselbrand",
            "Faithless Looting",
            "Show and Tell",
            "Force of Will",
            "Iona, Shield of Emeria",
            "Putrid Imp",
            "Careful Study",
            "Thoughtseize",
            "Jin-Gitaxias, Core Augur",
        ]
    )

    static let lands = MajorArchetype(
        id: "lands",
        name: "Lands",
        iconName: "leaf.fill",
        tintHex: "#52BE80",
        intro: "Lands turns lands into both ramp AND threats. Through the Breach into a 20/20 Marit Lage from Dark Depths, or grind out value with Life from the Loam recursion, this is the most unique combo-control hybrid in the format.",
        strategy: """
        The combo is Dark Depths + Thespian's Stage (or Vampire Hexmage). Thespian's Stage copies Dark Depths, the legend rule kills the original (now without counters), and you get a 20/20 indestructible flying token in play. With Mox Diamond ramp, this can happen on turn 2.

        The grindy plan uses Life from the Loam to recur fetchlands and Wastelands. You strand opponent on no mana while you draw 3 lands per turn cycle. Crop Rotation finds Dark Depths or Thespian's Stage at instant speed for the kill.

        Maze of Ith and Glacial Chasm shut down attackers. The Tabernacle at Pendrell Vale taxes their creatures into oblivion. You essentially play a control deck made entirely of lands.

        Sequencing: fetch lands at end-of-turn for Loam triggers, sandbag Thespian's Stage until you have Dark Depths counter-removal ready, and never let your opponent untap with mana if they have removal for the 20/20.
        """,
        matchTerms: ["lands"],
        signatureCards: [
            "Dark Depths",
            "Thespian's Stage",
            "Life from the Loam",
            "Crop Rotation",
            "Mox Diamond",
            "Wasteland",
            "Maze of Ith",
            "The Tabernacle at Pendrell Vale",
            "Glacial Chasm",
            "Exploration",
            "Punishing Fire",
            "Grove of the Burnwillows",
        ]
    )

    static let eldrazi = MajorArchetype(
        id: "eldrazi",
        name: "Eldrazi",
        iconName: "tentacle.fill",
        tintHex: "#566573",
        intro: "Eldrazi cheats out massive colorless threats using the Eldrazi Temple / Eye of Ugin engine, dropping 4-cost creatures on turn 2 and 8-mana finishers on turn 4. The format-defining engine of multiple banned cards.",
        strategy: """
        Eldrazi Temple and Eye of Ugin (where legal) reduce the cost of all Eldrazi spells. A turn-2 Thought-Knot Seer is the baseline — it strips a card from their hand and leaves a 4/4 body. Reality Smasher trades with anything and forces a discard if they remove it.

        Endless One is a flexible threat that scales with how much mana you have. Matter Reshaper provides card advantage when it dies. Smasher is the closer.

        The deck is essentially a midrange beatdown that ramps faster than anything else. You don't have a combo — you just play creatures bigger than your opponent's, faster than they can respond.

        Against control, Thought-Knot strips their answer; against aggro, Reality Smasher trades up. Against combo, you race them with Smasher beats and Karn, Scion of Urza for card advantage.

        The deck has fallen in and out of legality multiple times due to Eye of Ugin bans. Modern Eldrazi Tron is the most common modern variant.
        """,
        matchTerms: ["eldrazi"],
        signatureCards: [
            "Thought-Knot Seer",
            "Reality Smasher",
            "Eldrazi Temple",
            "Eye of Ugin",
            "Endless One",
            "Matter Reshaper",
            "Karn, Scion of Urza",
            "Walking Ballista",
            "Chalice of the Void",
            "Endbringer",
        ]
    )

    static let slivers = MajorArchetype(
        id: "slivers",
        name: "Slivers",
        iconName: "arrow.triangle.branch",
        tintHex: "#2ECC71",
        intro: "Slivers is Magic's ultimate tribal synergy deck. Every Sliver shares its abilities with every other Sliver you control, creating a hive-mind army where each new creature exponentially increases the power of the whole board.",
        strategy: """
        The core engine is cumulative keyword sharing. Crystalline Sliver gives every Sliver shroud. Muscle Sliver (or Sinew Sliver / Predatory Sliver) pumps the whole team +1/+1. Gemhide Sliver and Manaweft Sliver turn every Sliver into a mana dork, letting you chain 3-4 creatures per turn once you hit critical mass.

        In Commander, Sliver Overlord is the go-to general — it tutors for any Sliver and can steal opposing Slivers. Sliver Queen generates infinite tokens with Mana Echoes or Basal Sliver. Sliver Hivelord makes your entire board indestructible. Sliver Legion turns a modest board into a lethal alpha strike (+1/+1 for each other Sliver).

        Quick Sliver gives the hive flash, letting you play around sweepers. Heart Sliver grants haste so every new creature contributes immediately. Hibernation Sliver lets you bounce your own Slivers to dodge removal at the cost of life.

        The weakness is board wipes — a single Wrath effect resets your entire engine. Prioritize Crystalline Sliver (shroud) and Diffusion Sliver (tax on targeting) to protect the hive, and hold back a few Slivers in hand as insurance against sweepers.
        """,
        matchTerms: ["sliver", "slivers", "hive"],
        signatureCards: [
            "Sliver Overlord",
            "Sliver Queen",
            "Sliver Legion",
            "Sliver Hivelord",
            "Crystalline Sliver",
            "Muscle Sliver",
            "Sinew Sliver",
            "Predatory Sliver",
            "Gemhide Sliver",
            "Manaweft Sliver",
            "Hibernation Sliver",
            "Quick Sliver",
            "Heart Sliver",
            "Diffusion Sliver",
        ]
    )

    static let sneakAndShow = MajorArchetype(
        id: "sneak-and-show",
        name: "Sneak and Show",
        iconName: "wand.and.stars",
        tintHex: "#1F618D",
        intro: "Sneak and Show cheats Emrakul or Griselbrand into play through Show and Tell or Sneak Attack. A turn-1 Emrakul ends most games on the spot — your opponent has one turn to find an answer.",
        strategy: """
        The two enablers: Show and Tell puts a creature into play from your hand for three mana, and Sneak Attack puts one in until end of turn for one red mana per activation. With Sneak Attack, you can chain multiple Emrakuls if you survive long enough.

        Griselbrand is the safer threat — pay 7 life, draw 7 cards, then dig for protection or a second enabler. Emrakul is the win condition: a 15/15 with annihilator 6 that gives you an extra turn means almost certain victory.

        The deck is built around Force of Will + Daze + Brainstorm + Ponder protection package. You spend turns 1-2 setting up with cantrips and counterspell mana, then go off on turn 3.

        Against discard, your hand survives Force of Will. Against counterspell decks, Defense Grid and Boseiju, Who Shelters All force the cheat through. Against graveyard hate, you don't care — your threats are in your hand.
        """,
        matchTerms: ["sneak and show", "show and tell", "omnitell"],
        signatureCards: [
            "Show and Tell",
            "Sneak Attack",
            "Griselbrand",
            "Emrakul, the Aeons Torn",
            "Force of Will",
            "Daze",
            "Brainstorm",
            "Ponder",
            "Lotus Petal",
            "Defense Grid",
        ]
    )
}
