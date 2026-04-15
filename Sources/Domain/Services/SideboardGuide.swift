import Foundation

// MARK: - Sideboard Plan

struct SideboardPlan: Identifiable {
    var id: String { "\(format)-\(opponent)" }
    let format: String          // "modern", "legacy", "pioneer"
    let opponent: String        // "Burn", "Tron", etc.
    let opponentType: String    // "Aggro", "Combo", "Control", etc.
    let bringIn: [String]       // Card categories/names to bring in
    let takeOut: [String]       // Card categories/names to take out
    let strategy: String        // Brief strategy note
}

// MARK: - General Principle

struct SideboardPrinciple: Identifiable {
    var id: String { againstType }
    let againstType: String
    let bringIn: String
    let takeOut: String
    let principle: String
}

// MARK: - Sideboard Guide Data

struct SideboardGuideData {

    // MARK: All Plans

    static let plans: [SideboardPlan] = modernPlans + legacyPlans + pioneerPlans

    static func plans(for format: String) -> [SideboardPlan] {
        plans.filter { $0.format == format.lowercased() }
    }

    // MARK: Modern (10)

    static let modernPlans: [SideboardPlan] = [
        SideboardPlan(
            format: "modern", opponent: "Boros Energy", opponentType: "Aggro/Midrange",
            bringIn: ["Extra removal", "Celestial Purge", "Sweepers", "Lifegain"],
            takeOut: ["Slow card advantage", "Conditional counterspells", "Narrow combo pieces"],
            strategy: "Race or go bigger. Their energy engine snowballs — remove threats early."
        ),
        SideboardPlan(
            format: "modern", opponent: "Affinity", opponentType: "Aggro/Artifact",
            bringIn: ["Stony Silence", "Shatterstorm", "Ancient Grudge", "Wear // Tear"],
            takeOut: ["Narrow creature removal", "Slow card draw"],
            strategy: "Artifact hate wins games. Stony Silence is nearly lights-out."
        ),
        SideboardPlan(
            format: "modern", opponent: "Jeskai Blink", opponentType: "Midrange/Value",
            bringIn: ["Counterspells", "Planeswalkers", "Card advantage engines"],
            takeOut: ["Aggressive one-drops", "Burn spells", "Narrow removal"],
            strategy: "Out-grind them. Their blink loops are slow; resolve must-answer threats."
        ),
        SideboardPlan(
            format: "modern", opponent: "Eldrazi Tron", opponentType: "Ramp/Midrange",
            bringIn: ["Land destruction", "Blood Moon", "Damping Sphere", "Surgical Extraction"],
            takeOut: ["Small creature removal", "Lifegain", "Slow win conditions"],
            strategy: "Disrupt their mana. Blood Moon shuts off Tron lands and Eldrazi Temple."
        ),
        SideboardPlan(
            format: "modern", opponent: "Ruby Storm", opponentType: "Combo",
            bringIn: ["Counterspells", "Graveyard hate", "Damping Sphere", "Flusterstorm"],
            takeOut: ["Creature removal", "Sweepers", "Lifegain"],
            strategy: "Interact early. A single well-timed counter or hate piece stops the chain."
        ),
        SideboardPlan(
            format: "modern", opponent: "Amulet Titan", opponentType: "Combo/Ramp",
            bringIn: ["Blood Moon", "Alpine Moon", "Land destruction", "Surgical Extraction"],
            takeOut: ["Creature removal", "Lifegain", "Grindy midrange cards"],
            strategy: "Deny their lands. Blood Moon and bounce-land hate are devastating."
        ),
        SideboardPlan(
            format: "modern", opponent: "Izzet Prowess", opponentType: "Aggro/Tempo",
            bringIn: ["Cheap removal", "Sweepers", "Lifegain", "Engineered Explosives"],
            takeOut: ["Expensive sorceries", "Conditional counterspells", "Slow card draw"],
            strategy: "Stabilize. Remove their cheap threats before prowess triggers stack up."
        ),
        SideboardPlan(
            format: "modern", opponent: "Living End", opponentType: "Combo",
            bringIn: ["Graveyard hate", "Counterspells", "Leyline of the Void", "Rest in Peace"],
            takeOut: ["Spot removal", "Sweepers", "Lifegain"],
            strategy: "Graveyard hate is king. One Rest in Peace makes their deck non-functional."
        ),
        SideboardPlan(
            format: "modern", opponent: "Splinter Twin", opponentType: "Combo/Tempo",
            bringIn: ["Instant-speed removal", "Counterspells", "Torpor Orb", "Spellskite"],
            takeOut: ["Sorcery-speed removal", "Lifegain", "Slow threats"],
            strategy: "Hold up instant-speed interaction. Never tap out on their turn 4+."
        ),
        SideboardPlan(
            format: "modern", opponent: "Domain Zoo", opponentType: "Aggro",
            bringIn: ["Sweepers", "Lifegain", "Cheap removal", "Timely Reinforcements"],
            takeOut: ["Expensive card draw", "Thoughtseize", "Narrow combo pieces"],
            strategy: "Survive the blitz. Their manabase hurts them — capitalize on their life loss."
        ),
    ]

    // MARK: Legacy (8)

    static let legacyPlans: [SideboardPlan] = [
        SideboardPlan(
            format: "legacy", opponent: "Dimir Tempo", opponentType: "Tempo/Control",
            bringIn: ["Pyroblast", "Red Elemental Blast", "Extra removal", "Carpet of Flowers"],
            takeOut: ["Slow win conditions", "Excess discard", "Narrow hate"],
            strategy: "Resolve threats through Daze/Force. Pyroblast is your best card."
        ),
        SideboardPlan(
            format: "legacy", opponent: "Canadian Druid", opponentType: "Tempo",
            bringIn: ["Pyroblast", "Submerge", "Extra removal", "Sylvan Library"],
            takeOut: ["Combo pieces", "Slow card advantage", "Thoughtseize"],
            strategy: "Cheap answers for Delver and Mongoose. Don't let Nimble Mongoose go unanswered."
        ),
        SideboardPlan(
            format: "legacy", opponent: "Doomsday", opponentType: "Combo",
            bringIn: ["Force of Will", "Flusterstorm", "Surgical Extraction", "Mindbreak Trap"],
            takeOut: ["Creature removal", "Sweepers", "Lifegain"],
            strategy: "Counter the Doomsday itself. Surgical their Thassa's Oracle if they resolve it."
        ),
        SideboardPlan(
            format: "legacy", opponent: "Oops All Spells", opponentType: "Combo",
            bringIn: ["Force of Will", "Surgical Extraction", "Leyline of the Void", "Mindbreak Trap"],
            takeOut: ["All creature removal", "Lifegain", "Slow answers"],
            strategy: "Mulligan for Force or Leyline aggressively. They fold to graveyard hate."
        ),
        SideboardPlan(
            format: "legacy", opponent: "Eldrazi Aggro", opponentType: "Aggro/Stompy",
            bringIn: ["Swords to Plowshares", "Terminus", "Sweepers", "Karakas"],
            takeOut: ["Counterspells that miss", "Combo pieces", "Pyroblast"],
            strategy: "Their threats dodge Force. Use efficient white removal and sweepers."
        ),
        SideboardPlan(
            format: "legacy", opponent: "Trini Tron Karn", opponentType: "Ramp/Prison",
            bringIn: ["Wasteland", "Blood Moon", "Force of Vigor", "Null Rod"],
            takeOut: ["Small creature removal", "Pyroblast", "Narrow counters"],
            strategy: "Destroy their lands. Wasteland + Surgical on a Tron piece locks them out."
        ),
        SideboardPlan(
            format: "legacy", opponent: "8-Cast", opponentType: "Artifact/Combo",
            bringIn: ["Force of Vigor", "Null Rod", "Energy Flux", "Meltdown"],
            takeOut: ["Creature removal", "Pyroblast", "Slow win conditions"],
            strategy: "Mass artifact destruction. Null Rod shuts off their entire engine."
        ),
        SideboardPlan(
            format: "legacy", opponent: "Show and Tell", opponentType: "Combo",
            bringIn: ["Containment Priest", "Karakas", "Counterspells", "Ashen Rider"],
            takeOut: ["Creature removal", "Sweepers", "Thoughtseize (on the draw)"],
            strategy: "Counter Show and Tell or have Containment Priest/Karakas as insurance."
        ),
    ]

    // MARK: Pioneer (8)

    static let pioneerPlans: [SideboardPlan] = [
        SideboardPlan(
            format: "pioneer", opponent: "Izzet Prowess", opponentType: "Aggro/Tempo",
            bringIn: ["Cheap removal", "Sweepers", "Lifegain", "Aether Gust"],
            takeOut: ["Expensive sorceries", "Thoughtseize", "Slow threats"],
            strategy: "Remove their threats on sight. Don't let Monastery Swiftspear snowball."
        ),
        SideboardPlan(
            format: "pioneer", opponent: "Orzhov Greasefang", opponentType: "Combo",
            bringIn: ["Graveyard hate", "Rest in Peace", "Unlicensed Hearse", "Instant removal"],
            takeOut: ["Slow card draw", "Sweepers", "Lifegain"],
            strategy: "Exile their graveyard. Without Parhelion II in the yard, Greasefang does nothing."
        ),
        SideboardPlan(
            format: "pioneer", opponent: "RDW", opponentType: "Aggro",
            bringIn: ["Lifegain", "Cheap removal", "Sweepers", "Aether Gust"],
            takeOut: ["Thoughtseize", "Expensive card draw", "Slow win conditions"],
            strategy: "Stabilize by turn 4. Life gain buys critical turns; sweepers seal the deal."
        ),
        SideboardPlan(
            format: "pioneer", opponent: "Abzan Greasefang", opponentType: "Combo/Midrange",
            bringIn: ["Graveyard hate", "Rest in Peace", "Unlicensed Hearse", "Removal"],
            takeOut: ["Slow card draw", "Conditional counters", "Lifegain"],
            strategy: "Same as Orzhov Greasefang but they have a backup midrange plan. Stay flexible."
        ),
        SideboardPlan(
            format: "pioneer", opponent: "Golgari Midrange", opponentType: "Midrange",
            bringIn: ["Card advantage", "Planeswalkers", "Extra removal", "Sweepers"],
            takeOut: ["Narrow hate cards", "Cheap burn", "Excess aggro pieces"],
            strategy: "Go bigger. Out-grind their removal-heavy gameplan with card advantage."
        ),
        SideboardPlan(
            format: "pioneer", opponent: "Rogues", opponentType: "Tempo/Mill",
            bringIn: ["Cheap removal", "Sweepers", "Graveyard hate (for escape)", "Lifegain"],
            takeOut: ["Slow card draw", "Expensive threats", "Narrow counters"],
            strategy: "Kill their Rogues early. Without creatures, their mill plan stalls."
        ),
        SideboardPlan(
            format: "pioneer", opponent: "Azorius Control", opponentType: "Control",
            bringIn: ["Counterspells", "Discard", "Planeswalkers", "Mystical Dispute"],
            takeOut: ["Creature removal", "Sweepers", "Lifegain"],
            strategy: "Don't overextend into Supreme Verdict. Resolve one threat at a time."
        ),
        SideboardPlan(
            format: "pioneer", opponent: "Selesnya Company", opponentType: "Combo/Aggro",
            bringIn: ["Sweepers", "Instant-speed removal", "Grafdigger's Cage"],
            takeOut: ["Thoughtseize", "Slow card draw", "Narrow hate"],
            strategy: "Cage stops Collected Company. Sweepers punish their go-wide strategy."
        ),
    ]

    // MARK: General Principles

    static let generalPrinciples: [SideboardPrinciple] = [
        SideboardPrinciple(
            againstType: "Aggro",
            bringIn: "Lifegain, sweepers, extra cheap removal, efficient blockers",
            takeOut: "Expensive card draw, Thoughtseize/discard, slow win conditions",
            principle: "Survive the early game. Trade resources 1-for-1."
        ),
        SideboardPrinciple(
            againstType: "Control",
            bringIn: "Counterspells, discard, hard-to-answer threats, card advantage",
            takeOut: "Spot creature removal, sweepers, lifegain, redundant narrow answers",
            principle: "Don't overextend. Force through one threat at a time."
        ),
        SideboardPrinciple(
            againstType: "Combo",
            bringIn: "Disruption, graveyard hate, Stax pieces, counterspells",
            takeOut: "Slow creature removal, lifegain, grindy midrange cards",
            principle: "Speed + disruption. Present a clock while disrupting their combo."
        ),
        SideboardPrinciple(
            againstType: "Midrange",
            bringIn: "Card advantage, planeswalkers, 2-for-1 threats, sweepers",
            takeOut: "Narrow hate cards, excess cheap removal, reactive spells",
            principle: "Go bigger. Win the resource war."
        ),
        SideboardPrinciple(
            againstType: "Tempo",
            bringIn: "Cheap removal, sweepers, lifegain, hard-to-remove threats",
            takeOut: "Expensive sorceries, cards bad when behind, conditional counters",
            principle: "Stabilize. Remove their cheap threats efficiently."
        ),
    ]
}
