import SwiftUI

/// Multi-step screen: paste a card list → analyze format legality → create a deck.
/// Step 1: text input. Step 2: format breakdown. Step 3: create deck from legal cards.
struct DeckBuilderScreen: View {

    let cardRepository: CardRepositoryProtocol
    let deckRepository: DeckListRepository

    @State private var inputText = ""
    @State private var parsedCards: [ParsedEntry] = []
    @State private var isParsing = false
    @State private var showResults = false
    @State private var parseError: String?
    @State private var formatBreakdown: [FormatSuggestion] = []
    @State private var createdDeck: DeckList?
    @State private var isCreatingDeck = false
    @State private var analysisSaved = false
    /// Fetched reference decklists keyed by FormatSuggestion.id
    @State private var referenceDecklists: [UUID: MTGTop8Decklist] = [:]
    @State private var fetchingReferenceFor: UUID?
    @State private var referenceError: [UUID: String] = [:]
    @Environment(\.dismiss) private var dismiss

    private let mtgTop8Service: MTGTop8ServiceProtocol = MTGTop8Service()
    private let archetypeIndex = MTGTop8ArchetypeIndex()

    private static let archetypeSignatures: [(name: String, cards: Set<String>, formats: Set<String>, urls: [String: String])] = [
        ("Infect", ["Glistener Elf", "Blighted Agent", "Inkmoth Nexus", "Might of Old Krosa", "Scale Up", "Invigorate", "Berserk", "Noble Hierarch", "Vines of Vastwood", "Venerated Rotpriest", "Embiggen"], ["modern", "legacy", "pauper"],
         ["modern": "https://www.mtgtop8.com/archetype?a=195&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/infect",
          "legacy": "https://www.mtgtop8.com/archetype?a=32&meta=39",
          "legacy_alt": "https://www.mtggoldfish.com/archetype/legacy-infect",
          "pauper": "https://www.mtgtop8.com/archetype?a=538&meta=149",
          "pauper_alt": "https://www.mtggoldfish.com/archetype/pauper-infect"]),
        ("Burn", ["Lightning Bolt", "Goblin Guide", "Monastery Swiftspear", "Lava Spike", "Rift Bolt", "Eidolon of the Great Revel", "Searing Blaze", "Chain Lightning", "Price of Progress", "Fireblast"], ["modern", "legacy", "pauper", "premodern"],
         ["modern": "https://www.mtgtop8.com/archetype?a=186&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/burn-702f2852-b067-4480-98e0-05b0c8ae9567",
          "legacy": "https://www.mtgtop8.com/archetype?a=31&meta=39",
          "legacy_alt": "https://www.mtggoldfish.com/archetype/legacy-burn",
          "pauper": "https://www.mtgtop8.com/archetype?a=525&meta=149",
          "pauper_alt": "https://www.mtggoldfish.com/archetype/pauper-burn"]),
        ("Affinity", ["Cranial Plating", "Ornithopter", "Springleaf Drum", "Thoughtcast", "Myr Enforcer", "Frogmite", "Sojourner's Companion"], ["modern", "pauper"],
         ["modern": "https://www.mtgtop8.com/archetype?a=217&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/affinity",
          "pauper": "https://www.mtgtop8.com/archetype?a=539&meta=149",
          "pauper_alt": "https://www.mtggoldfish.com/archetype/pauper-affinity"]),
        ("Death's Shadow", ["Death's Shadow", "Street Wraith", "Thoughtseize", "Fatal Push", "Scourge of the Skyclaves"], ["modern", "legacy"],
         ["modern": "https://www.mtgtop8.com/archetype?a=370&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/deaths-shadow"]),
        ("Tron", ["Urza's Tower", "Urza's Mine", "Urza's Power Plant", "Karn Liberated", "Wurmcoil Engine"], ["modern"],
         ["modern": "https://www.mtgtop8.com/archetype?a=205&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/tron"]),
        ("Eldrazi Tron", ["Thought-Knot Seer", "Reality Smasher", "Matter Reshaper", "Eldrazi Temple", "Chalice of the Void", "Walking Ballista", "Endbringer", "All Is Dust", "Karn, the Great Creator", "Urza's Tower", "Urza's Mine", "Urza's Power Plant", "Ulamog, the Ceaseless Hunger", "Dismember"], ["modern"],
         ["modern": "https://www.mtgtop8.com/archetype?a=525&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/eldrazi-tron"]),
        ("Eldrazi Stompy", ["Thought-Knot Seer", "Reality Smasher", "Eldrazi Mimic", "Matter Reshaper", "Endless One", "Eldrazi Temple", "Eye of Ugin", "Chalice of the Void", "Ancient Tomb", "City of Traitors", "Simian Spirit Guide", "Umezawa's Jitte", "Cavern of Souls", "Dismember"], ["legacy"],
         ["legacy": "https://www.mtgtop8.com/archetype?a=549&meta=39",
          "legacy_alt": "https://www.mtggoldfish.com/archetype/legacy-eldrazi"]),
        ("Eldrazi Ramp", ["Thought-Knot Seer", "Reality Smasher", "Matter Reshaper", "Eldrazi Temple", "Ulamog, the Ceaseless Hunger", "Walking Ballista", "Hedron Crawler", "Spatial Contortion", "Scavenger Grounds", "Warping Wail", "Oblivion Sower", "Caves of Koilos"], ["pioneer"],
         ["pioneer": "https://www.mtgtop8.com/archetype?a=1200&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/pioneer-eldrazi-ramp"]),
        ("Storm", ["Grapeshot", "Past in Flames", "Baral, Chief of Compliance", "Gifts Ungiven", "Birgi, God of Storytelling"], ["modern", "legacy"],
         ["modern": "https://www.mtgtop8.com/archetype?a=182&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/storm",
          "legacy": "https://www.mtgtop8.com/archetype?a=51&meta=39",
          "legacy_alt": "https://www.mtggoldfish.com/archetype/legacy-storm"]),
        ("Elves", ["Llanowar Elves", "Elvish Mystic", "Heritage Druid", "Nettle Sentinel", "Craterhoof Behemoth", "Elvish Archdruid", "Priest of Titania", "Wirewood Symbiote", "Deranged Hermit"], ["modern", "legacy", "pauper", "premodern"],
         ["modern": "https://www.mtgtop8.com/archetype?a=261&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/elves",
          "legacy": "https://www.mtgtop8.com/archetype?a=21&meta=39",
          "legacy_alt": "https://www.mtggoldfish.com/archetype/legacy-elves"]),
        ("Goblins", ["Goblin Lackey", "Goblin Matron", "Goblin Ringleader", "Aether Vial", "Goblin Warchief", "Muxus, Goblin Grandee", "Goblin Piledriver", "Gempalm Incinerator", "Skirk Prospector", "Mogg Fanatic", "Siege-Gang Commander"], ["legacy", "modern", "premodern", "vintage"],
         ["legacy": "https://www.mtgtop8.com/archetype?a=22&meta=39",
          "legacy_alt": "https://www.mtggoldfish.com/archetype/legacy-goblins",
          "modern_alt": "https://www.mtggoldfish.com/archetype/goblins",
          "premodern": "https://www.mtgtop8.com/archetype?a=1479&meta=301&f=PREM",
          "premodern_alt": "https://www.mtggoldfish.com/archetype/premodern-goblins"]),
        ("Dredge", ["Narcomoeba", "Stinkweed Imp", "Golgari Grave-Troll", "Creeping Chill", "Prized Amalgam"], ["modern", "legacy"],
         ["modern": "https://www.mtgtop8.com/archetype?a=206&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/dredge",
          "legacy": "https://www.mtgtop8.com/archetype?a=2&meta=39",
          "legacy_alt": "https://www.mtggoldfish.com/archetype/legacy-dredge"]),
        ("Merfolk", ["Lord of Atlantis", "Master of the Pearl Trident", "Silvergill Adept", "Aether Vial", "Spreading Seas"], ["modern", "legacy"],
         ["modern": "https://www.mtgtop8.com/archetype?a=197&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/merfolk",
          "legacy": "https://www.mtgtop8.com/archetype?a=28&meta=39",
          "legacy_alt": "https://www.mtggoldfish.com/archetype/legacy-merfolk"]),

        // MARK: Pioneer Archetypes
        ("Izzet Phoenix", ["Arclight Phoenix", "Thing in the Ice", "Lightning Axe", "Treasure Cruise", "Chart a Course", "Fiery Temper", "Izzet Charm", "Opt", "Wild Slash", "Galvanic Iteration"], ["pioneer"],
         ["pioneer": "https://www.mtgtop8.com/archetype?a=881&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/izzet-phoenix-57eb17e3-2b71-4301-99a6-45002ffcfadb"]),
        ("Rakdos Midrange", ["Thoughtseize", "Fable of the Mirror-Breaker", "Sheoldred, the Apocalypse", "Fatal Push", "Bloodtithe Harvester", "Graveyard Trespasser", "Bonecrusher Giant", "Dreadbore", "Archfiend of the Dross"], ["pioneer"],
         ["pioneer": "https://www.mtgtop8.com/archetype?a=920&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/pioneer-rakdos-midrange"]),
        ("Lotus Field Combo", ["Lotus Field", "Thespian's Stage", "Hidden Strings", "Pore Over the Pages", "Lier, Disciple of the Drowned", "Vizier of Tumbling Sands", "Dark Petition", "Emergent Ultimatum"], ["pioneer"],
         ["pioneer": "https://www.mtgtop8.com/archetype?a=884&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/pioneer-lotus-field-combo"]),
        ("Greasefang Parhelion", ["Greasefang, Okiba Boss", "Parhelion II", "Can't Stay Away", "Raffine's Informant", "Charming Scoundrel", "Esika's Chariot", "Stitcher's Supplier", "Monument to Endurance"], ["pioneer"],
         ["pioneer": "https://www.mtgtop8.com/archetype?a=1317&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/pioneer-greasefang-parhelion"]),
        ("Spirits", ["Mausoleum Wanderer", "Supreme Phantom", "Spell Queller", "Rattlechains", "Selfless Spirit", "Collected Company", "Empyrean Eagle", "Shacklegeist", "Nebelgast Herald"], ["pioneer", "modern"],
         ["pioneer": "https://www.mtgtop8.com/archetype?a=881&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/pioneer-spirits",
          "modern": "https://www.mtgtop8.com/archetype?a=356&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/spirits"]),
        ("Mono-Green Devotion", ["Nykthos, Shrine to Nyx", "Cavalier of Thorns", "Old-Growth Troll", "Kiora, Behemoth Beckoner", "Storm the Festival", "Karn, the Great Creator", "Elvish Mystic", "Llanowar Elves"], ["pioneer"],
         ["pioneer": "https://www.mtgtop8.com/archetype?a=885&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/pioneer-mono-green-devotion"]),
        ("Azorius Control", ["Teferi, Hero of Dominaria", "Supreme Verdict", "Absorb", "The Wandering Emperor", "Shark Typhoon", "Memory Deluge", "Rest in Peace", "Dovin's Veto"], ["pioneer", "modern"],
         ["pioneer": "https://www.mtgtop8.com/archetype?a=883&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/pioneer-azorius-control",
          "modern": "https://www.mtgtop8.com/archetype?a=183&meta=51",
          "modern_alt": "https://www.mtggoldfish.com/archetype/azorius-control"]),

        // MARK: Vintage Archetypes
        ("Shops", ["Mishra's Workshop", "Lodestone Golem", "Trinisphere", "Thorn of Amethyst", "Phyrexian Revoker", "Walking Ballista", "Foundry Inspector", "Arcbound Ravager", "Nettlecyst"], ["vintage"],
         ["vintage": "https://www.mtgtop8.com/archetype?a=188&meta=48",
          "vintage_alt": "https://www.mtggoldfish.com/archetype/vintage-shops"]),
        ("Paradoxical Outcome", ["Paradoxical Outcome", "Mox Opal", "Mox Amber", "Sensei's Divining Top", "Monastery Mentor", "Time Vault", "Manifold Key", "Bolas's Citadel", "Tinker"], ["vintage"],
         ["vintage": "https://www.mtgtop8.com/archetype?a=661&meta=48",
          "vintage_alt": "https://www.mtggoldfish.com/archetype/vintage-paradoxical-outcome"]),
        ("Oath of Druids", ["Oath of Druids", "Forbidden Orchard", "Griselbrand", "Atraxa, Grand Unifier", "Show and Tell", "Force of Will", "Ancestral Recall", "Time Walk"], ["vintage"],
         ["vintage": "https://www.mtgtop8.com/archetype?a=189&meta=48",
          "vintage_alt": "https://www.mtggoldfish.com/archetype/vintage-oath"]),
        ("Vintage Dredge", ["Bazaar of Baghdad", "Narcomoeba", "Stinkweed Imp", "Golgari Grave-Troll", "Ichorid", "Bridge from Below", "Cabal Therapy", "Hollow One", "Prized Amalgam"], ["vintage"],
         ["vintage": "https://www.mtgtop8.com/archetype?a=190&meta=48",
          "vintage_alt": "https://www.mtggoldfish.com/archetype/vintage-dredge"]),
        ("Doomsday", ["Doomsday", "Thassa's Oracle", "Dark Ritual", "Force of Will", "Ancestral Recall", "Demonic Tutor", "Necropotence", "Street Wraith"], ["vintage"],
         ["vintage": "https://www.mtgtop8.com/archetype?a=709&meta=48",
          "vintage_alt": "https://www.mtggoldfish.com/archetype/vintage-doomsday"]),

        // MARK: Commander / cEDH Archetypes
        ("Thrasios/Tymna Midrange", ["Thrasios, Triton Hero", "Tymna the Weaver", "Thassa's Oracle", "Demonic Tutor", "Ad Nauseam", "Mana Crypt", "Chrome Mox", "Mox Diamond", "Rhystic Study", "Esper Sentinel"], ["commander"],
         ["commander": "https://www.mtgtop8.com/archetype?a=1050&meta=178",
          "commander_alt": "https://edhrec.com/commanders/thrasios-triton-hero-tymna-the-weaver"]),
        ("Kenrith Combo", ["Kenrith, the Returned King", "Thassa's Oracle", "Demonic Consultation", "Tainted Pact", "Ad Nauseam", "Silence", "Dockside Extortionist", "Underworld Breach", "Brain Freeze"], ["commander"],
         ["commander": "https://www.mtgtop8.com/archetype?a=1051&meta=178",
          "commander_alt": "https://edhrec.com/commanders/kenrith-the-returned-king"]),
        ("Najeela Tempo", ["Najeela, the Blade-Blossom", "Derevi, Empyrial Tactician", "Nature's Will", "Druids' Repository", "Sword of Feast and Famine", "Reconnaissance", "Esper Sentinel", "Rhystic Study", "Mystic Remora"], ["commander"],
         ["commander": "https://www.mtgtop8.com/archetype?a=1052&meta=178",
          "commander_alt": "https://edhrec.com/commanders/najeela-the-blade-blossom"]),
        ("Blue Farm", ["Kraum, Ludevic's Opus", "Tymna the Weaver", "Thassa's Oracle", "Demonic Consultation", "Ad Nauseam", "Dockside Extortionist", "Underworld Breach", "Brain Freeze", "Rhystic Study"], ["commander"],
         ["commander": "https://www.mtgtop8.com/archetype?a=1053&meta=178",
          "commander_alt": "https://edhrec.com/commanders/kraum-ludevics-opus-tymna-the-weaver"]),
        ("Kinnan Combo", ["Kinnan, Bonder Prodigy", "Basalt Monolith", "Mana Vault", "Sol Ring", "Thrasios, Triton Hero", "Thassa's Oracle", "Chrome Mox", "Mox Diamond", "Freed from the Real"], ["commander"],
         ["commander": "https://www.mtgtop8.com/archetype?a=1054&meta=178",
          "commander_alt": "https://edhrec.com/commanders/kinnan-bonder-prodigy"]),

        // MARK: Standard Archetypes
        ("Red Deck Wins", ["Monastery Swiftspear", "Kumano Faces Kakkazan", "Play with Fire", "Lightning Strike", "Embereth Veteran", "Slickshot Show-Off", "Monstrous Rage", "Heartfire Hero"], ["standard", "pioneer"],
         ["standard": "https://www.mtgtop8.com/archetype?a=1100&meta=58",
          "standard_alt": "https://www.mtggoldfish.com/archetype/standard-red-deck-wins",
          "pioneer": "https://www.mtgtop8.com/archetype?a=919&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/pioneer-red-deck-wins"]),
        ("Azorius Tempo", ["Watcher of the Spheres", "Spell Queller", "Lofty Denial", "Curious Obsession", "Rattlechains", "Empyrean Eagle", "Selfless Spirit", "Shacklegeist"], ["standard"],
         ["standard": "https://www.mtgtop8.com/archetype?a=1101&meta=58",
          "standard_alt": "https://www.mtggoldfish.com/archetype/standard-azorius-aggro"]),
        ("Simic Aggro", ["Evolving Adaptive", "Wildgrowth Walker", "Merfolk Branchwalker", "Jadelight Ranger", "Kumena, Tyrant of Orazca", "Deeproot Champion", "Deeproot Elite"], ["standard"],
         ["standard": "https://www.mtgtop8.com/archetype?a=1102&meta=58",
          "standard_alt": "https://www.mtggoldfish.com/archetype/standard-simic-aggro"]),
        ("Dimir Control", ["Go for the Throat", "Thoughtseize", "Memory Deluge", "Kaito Shizuki", "Sheoldred, the Apocalypse", "Cut Down", "Narset, Parter of Veils", "Hive of the Eye Tyrant"], ["standard", "pioneer"],
         ["standard": "https://www.mtgtop8.com/archetype?a=1103&meta=58",
          "standard_alt": "https://www.mtggoldfish.com/archetype/standard-dimir-control",
          "pioneer": "https://www.mtgtop8.com/archetype?a=921&meta=194",
          "pioneer_alt": "https://www.mtggoldfish.com/archetype/pioneer-dimir-control"]),
        ("Reanimator", ["Atraxa, Grand Unifier", "The Cruelty of Gix", "Breach the Multiverse", "Hostile Investigator", "Raffine, Scheming Seer", "Overlord of the Balemurk", "Deep-Cavern Bat"], ["standard"],
         ["standard": "https://www.mtgtop8.com/archetype?a=1104&meta=58",
          "standard_alt": "https://www.mtggoldfish.com/archetype/standard-reanimator"]),
    ]

    /// A parsed card entry with optional resolved Card from the database.
    struct ParsedEntry: Identifiable {
        let id = UUID()
        let name: String
        let quantity: Int
        let setCode: String?
        var card: Card?
    }

    /// Analysis result for a single format.
    struct FormatSuggestion: Identifiable {
        let id = UUID()
        let format: DeckFormat
        let legalCards: [(card: Card, quantity: Int)]
        let illegalCards: [(name: String, quantity: Int, reason: String)]
        let totalLegalQuantity: Int
        let deckSize: Int       // 60 or 100 for Commander
        let percentage: Double
        let archetypeName: String?
        let referenceURL: String?
        let altReferenceURL: String?  // MTGGoldfish fallback
        var suggestedDeckName: String {
            if let arch = archetypeName { return "\(format.displayName) \(arch)" }
            return "\(format.displayName) Build"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let deck = createdDeck {
                    DeckDetailView(
                        deck: deck,
                        repository: deckRepository,
                        cardRepository: cardRepository
                    )
                } else if showResults {
                    resultsView
                } else {
                    inputView
                }
            }
            .navigationTitle(createdDeck != nil ? "" : "Build from List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if createdDeck == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .disabled(isParsing || isCreatingDeck)
                    }
                }
                if !showResults && createdDeck == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Analyze") {
                            Task { await parseAndAnalyze() }
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                    }
                }
                if showResults && createdDeck == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit List") {
                            showResults = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste your card list")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.onBackground)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Text("Format: 4 Lightning Bolt [M11], or 4 Lightning Bolt")
                .font(MD3Typography.bodySmall)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .padding(.horizontal, 16)

            TextEditor(text: $inputText)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MD3Theme.outlineVariant, lineWidth: 1)
                )
                .padding(.horizontal, 16)

            if isParsing {
                HStack {
                    ProgressView()
                    Text("Resolving cards...")
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                .padding(.horizontal, 16)
            }

            if let parseError {
                Text(parseError)
                    .font(MD3Typography.bodySmall)
                    .foregroundStyle(MD3Theme.error)
                    .padding(.horizontal, 16)
            }

            Spacer()
        }
        .padding(.bottom, 16)
    }

    // MARK: - Results View

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                parseSummarySection

                // Format suggestions
                if formatBreakdown.isEmpty {
                    noFormatsView
                } else {
                    ForEach(formatBreakdown) { suggestion in
                        formatCard(suggestion)
                    }
                }

                // Save Analysis button
                if !formatBreakdown.isEmpty {
                    saveAnalysisSection
                }

                // Unresolved cards
                unresolvedSection
            }
            .padding(16)
        }
    }

    private var parseSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let resolved = parsedCards.filter { $0.card != nil }
            let totalQty = resolved.reduce(0) { $0 + $1.quantity }
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(MD3Theme.primary)
                    .font(.title3)
                Text("Parsed \(resolved.count) unique cards (\(totalQty) total)")
                    .font(MD3Typography.titleSmall)
                    .foregroundStyle(MD3Theme.onBackground)
            }
            let unresolved = parsedCards.filter { $0.card == nil }
            if !unresolved.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(MD3Theme.error).frame(width: 6, height: 6)
                    Text("\(unresolved.count) cards not found in database")
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.error)
                }
            }
        }
    }

    private var noFormatsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "xmark.circle")
                .font(.largeTitle)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Text("No format matches found")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func formatCard(_ suggestion: FormatSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(suggestion.suggestedDeckName)
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
                Text("\(Int(suggestion.percentage))%")
                    .font(MD3Typography.titleLarge)
                    .foregroundStyle(percentageColor(suggestion.percentage))
                    .monospacedDigit()
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MD3Theme.surfaceVariant)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(percentageColor(suggestion.percentage))
                        .frame(width: geo.size.width * min(suggestion.percentage / 100.0, 1.0), height: 8)
                }
            }
            .frame(height: 8)

            HStack(spacing: 12) {
                if let urlString = suggestion.referenceURL, let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("MTGTop8")
                        }
                        .font(.caption)
                        .foregroundStyle(MD3Theme.primary)
                    }
                }
                if let urlString = suggestion.altReferenceURL, let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text("MTGGoldfish")
                        }
                        .font(.caption)
                        .foregroundStyle(MD3Theme.primary)
                    }
                }
            }

            // Stats
            HStack(spacing: 16) {
                statLabel(
                    "\(suggestion.totalLegalQuantity) legal",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                statLabel(
                    "\(suggestion.illegalCards.reduce(0) { $0 + $1.quantity }) illegal",
                    icon: "xmark.circle.fill",
                    color: MD3Theme.error
                )
                Spacer()
                Text("of \(suggestion.deckSize)-card deck")
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

            // Top legal cards preview
            if !suggestion.legalCards.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    let preview = suggestion.legalCards.prefix(5)
                    ForEach(Array(preview.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 4) {
                            Text("\(entry.quantity)x")
                                .font(MD3Typography.labelSmall)
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                                .monospacedDigit()
                                .frame(width: 24, alignment: .trailing)
                            Text(entry.card.name)
                                .font(MD3Typography.bodySmall)
                                .foregroundStyle(MD3Theme.onSurface)
                                .lineLimit(1)
                        }
                    }
                    if suggestion.legalCards.count > 5 {
                        Text("+ \(suggestion.legalCards.count - 5) more")
                            .font(MD3Typography.labelSmall)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                            .padding(.leading, 28)
                    }
                }

                // Full decklist expandable
                DisclosureGroup {
                    fullDecklistView(suggestion.legalCards)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.primary)
                        Text("Full decklist (\(suggestion.legalCards.count) cards)")
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                    }
                }
            }

            // Reference decklist section
            if suggestion.archetypeName != nil {
                referenceDeckSection(suggestion)
            }

            // Build button
            if let refDeck = referenceDecklists[suggestion.id] {
                MD3FilledButton("Build Full \(suggestion.format.displayName) Deck") {
                    Task { await createDeckFromReference(suggestion: suggestion, reference: refDeck) }
                }
                .disabled(isCreatingDeck)
            } else if suggestion.totalLegalQuantity >= 10 {
                MD3FilledButton("Build \(suggestion.format.displayName) Deck") {
                    Task { await createDeck(from: suggestion) }
                }
                .disabled(isCreatingDeck)
            }
        }
        .padding(16)
        .background(MD3Theme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Groups legal cards by type line and shows them all.
    private func fullDecklistView(_ cards: [(card: Card, quantity: Int)]) -> some View {
        let grouped = Dictionary(grouping: cards) { entry -> String in
            let typeLine = entry.card.typeLine ?? ""
            if typeLine.lowercased().contains("creature") { return "Creatures" }
            if typeLine.lowercased().contains("instant") { return "Instants" }
            if typeLine.lowercased().contains("sorcery") { return "Sorceries" }
            if typeLine.lowercased().contains("enchantment") { return "Enchantments" }
            if typeLine.lowercased().contains("artifact") { return "Artifacts" }
            if typeLine.lowercased().contains("planeswalker") { return "Planeswalkers" }
            if typeLine.lowercased().contains("land") { return "Lands" }
            return "Other"
        }
        let order = ["Creatures", "Instants", "Sorceries", "Enchantments", "Artifacts", "Planeswalkers", "Lands", "Other"]
        let sortedGroups = order.compactMap { key -> (String, [(card: Card, quantity: Int)])? in
            guard let entries = grouped[key], !entries.isEmpty else { return nil }
            return (key, entries)
        }

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(sortedGroups, id: \.0) { groupName, entries in
                let groupQty = entries.reduce(0) { $0 + $1.quantity }
                Text("\(groupName) (\(groupQty))")
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.primary)
                    .padding(.top, 4)
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 4) {
                        Text("\(entry.quantity)x")
                            .font(MD3Typography.labelSmall)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                            .monospacedDigit()
                            .frame(width: 24, alignment: .trailing)
                        Text(entry.card.name)
                            .font(MD3Typography.bodySmall)
                            .foregroundStyle(MD3Theme.onSurface)
                            .lineLimit(1)
                        if let mana = entry.card.manaCost, !mana.isEmpty {
                            Spacer()
                            Text(mana)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(MD3Theme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }

    private func statLabel(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(text)
                .font(MD3Typography.labelSmall)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    private func percentageColor(_ pct: Double) -> Color {
        if pct >= 80 { return .green }
        if pct >= 50 { return .orange }
        return MD3Theme.error
    }

    @ViewBuilder
    private var unresolvedSection: some View {
        let unresolved = parsedCards.filter { $0.card == nil }
        if !unresolved.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(MD3Theme.error).frame(width: 8, height: 8)
                    Text("Not found (\(unresolved.count))")
                        .font(MD3Typography.labelMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                }
                Text("These cards were not found in the local database.")
                    .font(MD3Typography.bodySmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(unresolved) { entry in
                        Text("\(entry.quantity)x \(entry.name)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(MD3Theme.surfaceVariant.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Save Analysis

    private var saveAnalysisSection: some View {
        VStack(spacing: 8) {
            if analysisSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Analysis saved!")
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                }
                .padding(.vertical, 8)
            } else {
                MD3FilledButton("Save Analysis") {
                    saveCurrentAnalysis()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func saveCurrentAnalysis() {
        // Build the serializable results from the current formatBreakdown
        let results = formatBreakdown.map { suggestion -> AnalysisFormatResult in
            let legalCards = suggestion.legalCards.map { entry in
                AnalysisCard(
                    name: entry.card.name,
                    quantity: entry.quantity,
                    setCode: entry.card.set.code,
                    reason: nil
                )
            }
            let illegalCards = suggestion.illegalCards.map { entry in
                AnalysisCard(
                    name: entry.name,
                    quantity: entry.quantity,
                    setCode: nil,
                    reason: entry.reason
                )
            }
            return AnalysisFormatResult(
                format: suggestion.format.rawValue,
                displayName: suggestion.format.displayName,
                archetypeName: suggestion.archetypeName,
                referenceURL: suggestion.referenceURL,
                suggestedDeckName: suggestion.suggestedDeckName,
                legalCards: legalCards,
                illegalCards: illegalCards,
                totalLegalQuantity: suggestion.totalLegalQuantity,
                deckSize: suggestion.deckSize,
                percentage: suggestion.percentage
            )
        }

        // Auto-generate a title from the best archetype match or generic
        let bestFormat = formatBreakdown.first
        let title: String
        if let archetype = bestFormat?.archetypeName {
            title = "\(archetype) Analysis"
        } else if let formatName = bestFormat?.format.displayName {
            title = "\(formatName) List Analysis"
        } else {
            title = "Card Analysis"
        }

        _ = try? deckRepository.saveAnalysis(
            title: title,
            rawCardList: inputText,
            results: results
        )
        analysisSaved = true
    }

    // MARK: - Parse & Analyze

    private func parseAndAnalyze() async {
        isParsing = true
        parseError = nil
        defer { isParsing = false }

        // Normalize smart quotes
        let normalized = inputText
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")

        let lines = normalized.components(separatedBy: .newlines)
        var entries: [ParsedEntry] = []

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("//") { continue }
            if trimmed.lowercased() == "sideboard" || trimmed.lowercased() == "mainboard" { continue }

            guard let parsed = OrderPasteParser.parseLine(trimmed) else { continue }

            // Resolve the card against the database
            let card = await resolveCard(name: parsed.name, setCode: parsed.setCode)
            entries.append(ParsedEntry(
                name: parsed.name,
                quantity: parsed.quantity,
                setCode: parsed.setCode,
                card: card
            ))
        }

        if entries.isEmpty {
            parseError = "No valid card lines found. Use format: 4 Lightning Bolt"
            return
        }

        parsedCards = entries
        formatBreakdown = analyzeFormats(entries: entries)
        showResults = true

        // Auto-save analysis immediately
        saveCurrentAnalysis()
    }

    /// Resolves a card name (with optional set code) against the database.
    private func resolveCard(name: String, setCode: String?) async -> Card? {
        // Try exact set match first
        if let setCode {
            let variants = (try? await cardRepository.findVariants(name: name, setCode: setCode)) ?? []
            if let first = variants.first { return first }
        }

        // Any printing
        let printings = (try? await cardRepository.findAllPrintings(name: name)) ?? []
        if let first = printings.first { return first }

        // Fuzzy fallback
        if let card = try? await cardRepository.identifyCard(name: name) {
            return card
        }
        return try? await cardRepository.findFuzzyMatch(name: name)
    }

    /// Analyzes resolved cards against each non-freeform format.
    private func analyzeFormats(entries: [ParsedEntry]) -> [FormatSuggestion] {
        let resolved = entries.filter { $0.card != nil }
        guard !resolved.isEmpty else { return [] }

        let formats: [DeckFormat] = [.modern, .legacy, .pioneer, .standard, .pauper, .commander, .vintage, .premodern]
        var suggestions: [FormatSuggestion] = []

        for format in formats {
            guard let key = format.scryfallKey else { continue }
            let deckSize = format.minDeckSize ?? 60

            var legal: [(card: Card, quantity: Int)] = []
            var illegal: [(name: String, quantity: Int, reason: String)] = []
            let isCommanderFormat = format == .commander
            let basicLands: Set<String> = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"]

            for entry in resolved {
                guard let card = entry.card else { continue }
                let status = card.legalities.status(for: key)
                switch status {
                case .legal:
                    // Commander is singleton: cap non-basic-land cards at 1 copy
                    if isCommanderFormat && !basicLands.contains(card.name) {
                        legal.append((card: card, quantity: min(entry.quantity, 1)))
                    } else {
                        legal.append((card: card, quantity: entry.quantity))
                    }
                case .banned:
                    illegal.append((name: entry.name, quantity: entry.quantity, reason: "Banned"))
                case .restricted:
                    // Restricted means legal but limited to 1 copy
                    legal.append((card: card, quantity: min(entry.quantity, 1)))
                    if entry.quantity > 1 {
                        illegal.append((name: entry.name, quantity: entry.quantity - 1, reason: "Restricted (max 1)"))
                    }
                default:
                    illegal.append((name: entry.name, quantity: entry.quantity, reason: "Not legal"))
                }
            }

            let totalLegal = legal.reduce(0) { $0 + $1.quantity }
            let pct = Double(totalLegal) / Double(deckSize) * 100.0

            // Detect archetype
            let userCardNames = Set(legal.map { $0.card.name })
            var bestArchetype: (name: String, url: String?, altURL: String?, confidence: Double) = ("", nil, nil, 0)
            for sig in Self.archetypeSignatures {
                guard sig.formats.contains(key) else { continue }
                let overlap = sig.cards.intersection(userCardNames).count
                let confidence = Double(overlap) / Double(sig.cards.count)
                if confidence > bestArchetype.confidence && confidence >= 0.3 {
                    bestArchetype = (sig.name, sig.urls[key], sig.urls[key + "_alt"], confidence)
                }
            }

            // Only include formats where at least some cards are legal
            if totalLegal > 0 {
                suggestions.append(FormatSuggestion(
                    format: format,
                    legalCards: legal.sorted { $0.quantity > $1.quantity },
                    illegalCards: illegal,
                    totalLegalQuantity: totalLegal,
                    deckSize: deckSize,
                    percentage: min(pct, 100.0),
                    archetypeName: bestArchetype.confidence >= 0.3 ? bestArchetype.name : nil,
                    referenceURL: bestArchetype.url,
                    altReferenceURL: bestArchetype.altURL
                ))
            }
        }

        // Sort by percentage descending
        return suggestions.sorted { $0.percentage > $1.percentage }
    }

    // MARK: - Reference Decklist

    /// Maps DeckFormat to MTGTop8 format codes used by the service.
    /// `meta=51` → "MO" (Modern), etc.
    private func mtgTop8FormatCode(for format: DeckFormat) -> String {
        switch format {
        case .modern:    return "MO"
        case .legacy:    return "LE"
        case .vintage:   return "VI"
        case .standard:  return "ST"
        case .pioneer:   return "PI"
        case .pauper:    return "PAU"
        case .commander: return "EDH"
        case .premodern: return "PREM"
        default:         return "MO"
        }
    }

    /// Button + view for fetching and displaying a reference decklist.
    @ViewBuilder
    private func referenceDeckSection(_ suggestion: FormatSuggestion) -> some View {
        let isFetching = fetchingReferenceFor == suggestion.id

        if let refDeck = referenceDecklists[suggestion.id] {
            // Show the comparison view
            referenceDeckComparisonView(suggestion: suggestion, reference: refDeck)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { await fetchReferenceDecklist(for: suggestion) }
                } label: {
                    HStack(spacing: 6) {
                        if isFetching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.doc")
                                .font(.caption)
                        }
                        Text("Fetch Competitive Decklist")
                            .font(MD3Typography.labelMedium)
                    }
                    .foregroundStyle(MD3Theme.primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(MD3Theme.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(isFetching)

                if let error = referenceError[suggestion.id] {
                    Text(error)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.error)
                }
            }
        }
    }

    /// Fetches the top competitive decklist for a format suggestion's archetype.
    ///
    /// Instead of relying on hardcoded archetype IDs (which go stale when
    /// MTGTop8 reassigns them), this dynamically looks up the archetype by
    /// name using `MTGTop8ArchetypeIndex` — the same index the app already
    /// scrapes from MTGTop8's search page.
    private func fetchReferenceDecklist(for suggestion: FormatSuggestion) async {
        guard let archetypeName = suggestion.archetypeName else {
            referenceError[suggestion.id] = "No archetype identified for this format"
            return
        }

        fetchingReferenceFor = suggestion.id
        referenceError[suggestion.id] = nil
        defer { fetchingReferenceFor = nil }

        let formatCode = mtgTop8FormatCode(for: suggestion.format)
        guard let mtgFormat = MTGTop8Format(rawValue: formatCode) else {
            referenceError[suggestion.id] = "Unsupported format: \(suggestion.format.displayName)"
            return
        }

        do {
            // Search the archetype index for a matching archetype name
            let matches = try await archetypeIndex.search(archetypeName, in: [mtgFormat], limit: 1)

            // Fallback: if dynamic search fails, extract archetype ID from hardcoded URL
            var archetypeID: String
            if let matched = matches.first {
                archetypeID = String(matched.archetypeID)
            } else if let refURL = suggestion.referenceURL,
                      let range = refURL.range(of: "a=") {
                let afterA = refURL[range.upperBound...]
                let idStr = String(afterA.prefix(while: { $0.isNumber }))
                if !idStr.isEmpty {
                    archetypeID = idStr
                    print("[DeckBuilder] Dynamic search failed, using hardcoded archetype ID \(idStr) from URL")
                } else {
                    referenceError[suggestion.id] = "Archetype '\(archetypeName)' not found on MTGTop8 for \(suggestion.format.displayName)"
                    return
                }
            } else {
                referenceError[suggestion.id] = "Archetype '\(archetypeName)' not found on MTGTop8 for \(suggestion.format.displayName)"
                return
            }

            // Fetch the most recent deck for this archetype
            guard let topDeck = try await mtgTop8Service.fetchMostRecentDeck(
                archetypeID: archetypeID,
                format: formatCode
            ) else {
                referenceError[suggestion.id] = "No decks found for \(archetypeName)"
                return
            }

            let decklist = try await mtgTop8Service.fetchDecklist(deckID: topDeck.deckID)

            if decklist.mainboard.isEmpty {
                referenceError[suggestion.id] = "Empty decklist returned"
                return
            }

            referenceDecklists[suggestion.id] = decklist
        } catch {
            referenceError[suggestion.id] = "Failed to fetch: \(error.localizedDescription)"
        }
    }

    /// Displays the full reference decklist with owned/missing markers.
    private func referenceDeckComparisonView(suggestion: FormatSuggestion, reference: MTGTop8Decklist) -> some View {
        let userCardNames = buildUserCardNameSet()
        let mainboardTotal = reference.mainboard.reduce(0) { $0 + $1.quantity }
        let sideboardTotal = reference.sideboard.reduce(0) { $0 + $1.quantity }
        let mainboardOwned = reference.mainboard.reduce(0) { total, entry in
            total + (userCardNames[normalizeCardName(entry.cardName)] != nil ? min(entry.quantity, userCardNames[normalizeCardName(entry.cardName)]!) : 0)
        }
        let sideboardOwned = reference.sideboard.reduce(0) { total, entry in
            total + (userCardNames[normalizeCardName(entry.cardName)] != nil ? min(entry.quantity, userCardNames[normalizeCardName(entry.cardName)]!) : 0)
        }

        return VStack(alignment: .leading, spacing: 10) {
            // Summary header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(MD3Theme.primary)
                Text("Reference Decklist")
                    .font(MD3Typography.titleSmall)
                    .foregroundStyle(MD3Theme.onSurface)
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("\(mainboardOwned)/\(mainboardTotal) main")
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("\(sideboardOwned)/\(sideboardTotal) side")
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                Spacer()
                let totalOwned = mainboardOwned + sideboardOwned
                let totalCards = mainboardTotal + sideboardTotal
                Text("\(totalOwned)/\(totalCards) total")
                    .font(MD3Typography.labelMedium)
                    .foregroundStyle(MD3Theme.primary)
                    .monospacedDigit()
            }

            // Progress bar for total ownership
            let totalOwned = Double(mainboardOwned + sideboardOwned)
            let totalCards = Double(mainboardTotal + sideboardTotal)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MD3Theme.surfaceVariant)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.green)
                        .frame(width: geo.size.width * min(totalOwned / max(totalCards, 1), 1.0), height: 6)
                }
            }
            .frame(height: 6)

            // Mainboard
            DisclosureGroup {
                referenceCardList(entries: reference.mainboard, userCards: userCardNames)
            } label: {
                HStack(spacing: 4) {
                    Text("Mainboard (\(mainboardOwned)/\(mainboardTotal))")
                        .font(MD3Typography.labelMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                }
            }

            // Sideboard
            if !reference.sideboard.isEmpty {
                DisclosureGroup {
                    referenceCardList(entries: reference.sideboard, userCards: userCardNames)
                } label: {
                    HStack(spacing: 4) {
                        Text("Sideboard (\(sideboardOwned)/\(sideboardTotal))")
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                    }
                }
            }
        }
        .padding(12)
        .background(MD3Theme.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Renders a list of reference deck entries with owned/missing indicators.
    private func referenceCardList(entries: [MTGTop8DecklistEntry], userCards: [String: Int]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(entries) { entry in
                let key = normalizeCardName(entry.cardName)
                let owned = userCards[key] ?? 0
                let hasEnough = owned >= entry.quantity

                HStack(spacing: 6) {
                    // Status icon
                    Image(systemName: hasEnough ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(hasEnough ? .green : MD3Theme.error)

                    // Quantity
                    Text("\(entry.quantity)")
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .monospacedDigit()
                        .frame(width: 16, alignment: .trailing)

                    // Card name
                    Text(entry.cardName)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(hasEnough ? MD3Theme.onSurface : MD3Theme.onSurfaceVariant)
                        .lineLimit(1)

                    Spacer()

                    // Ownership detail
                    if hasEnough {
                        Text("Have \(owned)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.8))
                    } else if owned > 0 {
                        Text("Have \(owned)/\(entry.quantity)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.orange)
                    } else {
                        Text("Missing")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(MD3Theme.error)
                    }
                }
            }
        }
    }

    /// Builds a `[normalized card name: total quantity]` map from the user's parsed card list.
    /// Normalizes names by lowercasing and stripping special characters for fuzzy matching.
    private func buildUserCardNameSet() -> [String: Int] {
        var result: [String: Int] = [:]
        for entry in parsedCards {
            let key = normalizeCardName(entry.name)
            result[key, default: 0] += entry.quantity
        }
        return result
    }

    /// Normalizes a card name for comparison: lowercase, strip special chars.
    private func normalizeCardName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")  // smart quote
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2013}", with: "-")  // en-dash
            .replacingOccurrences(of: "\u{2014}", with: "-")  // em-dash
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Create Deck from Reference

    /// Creates a deck from the FULL reference decklist. Cards the user owns
    /// are marked "Arrived", missing cards are marked "Needed".
    private func createDeckFromReference(suggestion: FormatSuggestion, reference: MTGTop8Decklist) async {
        isCreatingDeck = true
        defer { isCreatingDeck = false }

        let formatStored = suggestion.format.rawValue
        guard let deck = try? deckRepository.createDeck(
            name: suggestion.suggestedDeckName,
            format: formatStored
        ) else { return }

        deck.referenceURL = suggestion.referenceURL

        let userCards = buildUserCardNameSet()
        let isCommander = suggestion.format == .commander
        let basicLands: Set<String> = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"]

        // Process mainboard + sideboard
        let allEntries: [(entry: MTGTop8DecklistEntry, zone: String)] =
            reference.mainboard.map { ($0, "mainboard") } +
            reference.sideboard.map { ($0, "sideboard") }

        for (entry, zone) in allEntries {
            let key = normalizeCardName(entry.cardName)
            // Commander is singleton: cap non-basic-land cards at 1 copy
            let qty = (isCommander && !basicLands.contains(entry.cardName)) ? min(entry.quantity, 1) : entry.quantity
            let ownedQty = userCards[key] ?? 0
            let hasEnough = ownedQty >= qty

            // Try to resolve the card from the database
            let resolved = await resolveCard(name: entry.cardName, setCode: nil)

            if let card = resolved {
                if let item = try? deckRepository.addItem(card: card, quantity: qty, to: deck, zone: zone) {
                    item.statusRaw = hasEnough ? "arrived" : "needed"
                    // Mark remaining copies too (addItem creates N individual copies)
                    let allItems = deck.items.filter { $0.cardName == card.name }
                    for deckItem in allItems.suffix(qty) {
                        deckItem.statusRaw = hasEnough ? "arrived" : "needed"
                    }
                }
            } else {
                // Card not in DB — add by name only
                _ = try? deckRepository.addItemByName(
                    cardName: entry.cardName,
                    quantity: qty,
                    status: hasEnough ? .arrived : .needed,
                    zone: zone,
                    to: deck
                )
            }
        }

        createdDeck = deck
    }

    // MARK: - Create Deck

    private func createDeck(from suggestion: FormatSuggestion) async {
        isCreatingDeck = true
        defer { isCreatingDeck = false }

        let formatStored = suggestion.format.rawValue
        guard let deck = try? deckRepository.createDeck(
            name: suggestion.suggestedDeckName,
            format: formatStored
        ) else { return }

        deck.referenceURL = suggestion.referenceURL

        let isCommander = suggestion.format == .commander
        let basicLands: Set<String> = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"]

        // Add all legal cards — mark as arrived since user already owns these
        // Commander is singleton: cap non-basic-land cards at 1 copy
        for entry in suggestion.legalCards {
            let qty: Int
            if isCommander && !basicLands.contains(entry.card.name) {
                qty = 1
            } else {
                qty = entry.quantity
            }
            if let item = try? deckRepository.addItem(card: entry.card, quantity: qty, to: deck) {
                item.statusRaw = "arrived"
            }
        }

        createdDeck = deck
    }
}
