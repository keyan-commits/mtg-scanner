import Foundation

// MARK: - Secret Lair Lands

/// Individual Secret Lair basic-land drops, each with its own collector-number
/// range so only that drop's printings are resolved from the shared "sld" set code.
/// Collector numbers verified against Scryfall API (is:reserved query on SLD set).
enum SecretLairLands {

    static let all: [LandCategory] = [
        astrologyLands,
        kozyndan,
        pixelSnowLands,
        godzillaLands,
        unfathomableCrushingBrutality,
        transformers,
        garyBaseman,
        shadesNotIncluded,
        arcane,
        postMalone,
        pixelLandsV2,
        jungShan,
        fullTextLands,
        eldraineWonderland,
        bobRoss,
        draculaLands,
        fortniteLands,
        pixelSnowV2,
        scottBalmer,
        brainDeadGage,
        brainDeadHank,
        spongeBob,
        flowerPower,
        spiderMan,
        kexp,
        dndLands,
        alanynaDannerArtist,
        mountainGoats,
        kelogsloops,
    ]

    // MARK: - The Astrology Lands (Jeanne D'Angelo)

    static let astrologyLands = LandCategory(
        id: "sld-astrology",
        name: "The Astrology Lands",
        iconName: "star.circle.fill",
        description: "Zodiac-themed lands by Jeanne D'Angelo (2022). 12 monthly releases, one per zodiac sign. Each features a distinctive colorful Japanese-inspired cityscape. Among the most valuable Secret Lair basics. Sources: Scryfall, CoolStuffInc.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["384", "385", "386", "387", "388", "389", "390", "391", "392", "393", "394", "395"]
    )

    // MARK: - Special Guest: Kozyndan

    static let kozyndan = LandCategory(
        id: "sld-kozyndan",
        name: "Special Guest: Kozyndan",
        iconName: "paintbrush.pointed.fill",
        description: "Japanese-influenced art by married artist duo kozyndan (2022). Calm, serene visual style with striking compositions. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1130", "1131", "1132", "1133", "1134"]
    )

    // MARK: - PixelSnowLands (Paradise Frost)

    static let pixelSnowLands = LandCategory(
        id: "sld-pixel-snow",
        name: "PixelSnowLands.jpg",
        iconName: "snowflake",
        description: "Pixel art snow-covered basics by Jubilee (2021). Retro Windows-era video game aesthetic. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp", "Snow-Covered Mountain", "Snow-Covered Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["325", "326", "327", "328", "329"]
    )

    // MARK: - The Godzilla Lands

    static let godzillaLands = LandCategory(
        id: "sld-godzilla",
        name: "The Godzilla Lands",
        iconName: "flame.fill",
        description: "Godzilla/kaiju IP crossover lands (2020). Japanese-language cards by Lars Grant-West, Jonas De Ro, Lucas Graciano, Grzegorz Rutkowski, and Ravenna Tran. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["63", "64", "65", "66", "67"]
    )

    // MARK: - The Unfathomable Crushing Brutality of Basic Lands

    static let unfathomableCrushingBrutality = LandCategory(
        id: "sld-brutality",
        name: "Unfathomable Crushing Brutality",
        iconName: "bolt.fill",
        description: "Dark metal/goth-inspired basic lands by Mark Riddick (2021). Heavy, brutal aesthetic. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["239", "240", "241", "242", "243"]
    )

    // MARK: - Transformers Lands

    static let transformers = LandCategory(
        id: "sld-transformers",
        name: "Transformers Lands",
        iconName: "gearshape.fill",
        description: "Transformers IP crossover lands (2022) by David Sondered and Joana LaFuente. Universes Beyond release. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1088", "1089", "1090", "1091", "1092"]
    )

    // MARK: - Featuring: Gary Baseman

    static let garyBaseman = LandCategory(
        id: "sld-baseman",
        name: "Featuring: Gary Baseman",
        iconName: "theatermasks.fill",
        description: "Surreal cartoon art by Gary Baseman (2023), known for Cranium board game. Uniquely weird and whimsical. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1382", "1383", "1384", "1385", "1386"]
    )

    // MARK: - Shades Not Included

    static let shadesNotIncluded = LandCategory(
        id: "sld-shades",
        name: "Shades Not Included",
        iconName: "sun.max.fill",
        description: "Synthwave/retrowave neon basics by Ben Schnuck (2022). Vibrant neon aesthetic. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["415", "416", "417", "418", "419"]
    )

    // MARK: - Secret Lair x Arcane

    static let arcane = LandCategory(
        id: "sld-arcane",
        name: "Secret Lair x Arcane",
        iconName: "sparkle",
        description: "League of Legends / Arcane Netflix series crossover (2021) by Riot Games. Universes Beyond. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["484", "485", "486", "487", "488"]
    )

    // MARK: - Secret Lair x Post Malone

    static let postMalone = LandCategory(
        id: "sld-post-malone",
        name: "Secret Lair x Post Malone",
        iconName: "music.note",
        description: "Post Malone collaboration (2022) featuring classic MTG artists Mark Poole, Fred Fields, Ron Spears, Donato Giancola, and Drew Tucker. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1190", "1191", "1192", "1193", "1194"]
    )

    // MARK: - PixelLands_v02.jpg

    static let pixelLandsV2 = LandCategory(
        id: "sld-pixel-v2",
        name: "PixelLands_v02.jpg",
        iconName: "square.grid.3x3.fill",
        description: "Pixel art regular basics by Jubilee (2023). Sequel to PixelSnowLands, non-snow edition. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1468", "1469", "1470", "1471", "1472"]
    )

    // MARK: - Featuring: JungShan

    static let jungShan = LandCategory(
        id: "sld-jungshan",
        name: "Featuring: JungShan",
        iconName: "mountain.2.fill",
        description: "East Asian watercolor/ink painting style basics by JungShan (2023). Dramatic, sweeping traditional Asian landscapes. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1399", "1400", "1401", "1402", "1403"]
    )

    // MARK: - The Full-Text Lands

    static let fullTextLands = LandCategory(
        id: "sld-full-text",
        name: "The Full-Text Lands",
        iconName: "text.justify.left",
        description: "Novelty lands with massive text boxes exhaustively explaining how basic lands work (2022). A humorous take on Magic's rules text — intentionally art-free. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["254", "255", "256", "257", "258"]
    )

    // MARK: - Eldraine Wonderland

    static let eldraineWonderland = LandCategory(
        id: "sld-eldraine",
        name: "Eldraine Wonderland",
        iconName: "wand.and.stars",
        description: "Snow-covered basics by Alayna Danner (2019). Among the very first Secret Lair drops. Fairy tale winter landscapes. Sources: Scryfall.",
        cardNames: ["Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp", "Snow-Covered Mountain", "Snow-Covered Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1", "2", "3", "4", "5"]
    )

    // MARK: - Happy Little Gathering (Bob Ross)

    static let bobRoss = LandCategory(
        id: "sld-bob-ross",
        name: "Happy Little Gathering",
        iconName: "paintpalette.fill",
        description: "Bob Ross collaboration (2020). Two art variants per basic land type using Bob Ross paintings. 'Happy little trees.' Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["100", "101", "102", "103", "104", "105", "106", "107", "108", "109"]
    )

    // MARK: - The Dracula Lands

    static let draculaLands = LandCategory(
        id: "sld-dracula",
        name: "The Dracula Lands",
        iconName: "moon.fill",
        description: "Gothic horror-themed basics (2022) by Donato Giancola, Yeong-Hao Han, Jonas De Ro, Grzegorz Rutkowski, and Andreas Rocha. Crimson Vow tie-in. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["359", "360", "361", "362", "363"]
    )

    // MARK: - Secret Lair x Fortnite

    static let fortniteLands = LandCategory(
        id: "sld-fortnite",
        name: "Secret Lair x Fortnite",
        iconName: "gamecontroller.fill",
        description: "Fortnite IP crossover: Landmarks and Locations (2022) by Alexander Kintner, Roberto Gatto, and Kevin Gnutzmans. Universes Beyond. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["448", "449", "450", "451", "452"]
    )

    // MARK: - PixelSnowLands v2 (ELK64)

    static let pixelSnowV2 = LandCategory(
        id: "sld-pixel-snow-v2",
        name: "PixelSnowLands v2 (ELK64)",
        iconName: "snowflake.circle.fill",
        description: "Pixel art snow-covered basics by ELK64 (2023). Commodore 64 inspired aesthetic. Second snow pixel lands set. Sources: Scryfall.",
        cardNames: ["Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp", "Snow-Covered Mountain", "Snow-Covered Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1473", "1474", "1475", "1476", "1477"]
    )

    // MARK: - The Strange Sands (Scott Balmer)

    static let scottBalmer = LandCategory(
        id: "sld-balmer",
        name: "The Strange Sands",
        iconName: "leaf.fill",
        description: "Serene nature scenes by Scott Balmer (2023). Sold individually via Chaos Vault. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1478", "1479", "1480", "1481", "1482"]
    )

    // MARK: - Secret Lair x Brain Dead (Gage Lindsten)

    static let brainDeadGage = LandCategory(
        id: "sld-braindead-gage",
        name: "Brain Dead: Gage Lindsten",
        iconName: "brain.fill",
        description: "Brain Dead streetwear collaboration (2024). Art by Gage Lindsten. Contemporary landscape art. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1647", "1648", "1649", "1650", "1651"]
    )

    // MARK: - Secret Lair x Brain Dead (Hank Reavis)

    static let brainDeadHank = LandCategory(
        id: "sld-braindead-hank",
        name: "Brain Dead: Hank Reavis",
        iconName: "brain.fill",
        description: "Brain Dead streetwear collaboration (2024). Art by Hank Reavis. Contemporary landscape art. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1652", "1653", "1654", "1655", "1656"]
    )

    // MARK: - Secret Lair x SpongeBob

    static let spongeBob = LandCategory(
        id: "sld-spongebob",
        name: "Secret Lair x SpongeBob",
        iconName: "water.waves",
        description: "SpongeBob SquarePants: Lands Under the Sea (2025) by Jon Vermilyea. Universes Beyond. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1939", "1940", "1941", "1942", "1943"]
    )

    // MARK: - Flower Power (Ashley Dreyfus)

    static let flowerPower = LandCategory(
        id: "sld-flower-power",
        name: "Flower Power",
        iconName: "camera.macro",
        description: "Poster-style floral basics by Ashley Dreyfus (2025). Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1945", "1946", "1947", "1948", "1949"]
    )

    // MARK: - Secret Lair x Spider-Man

    static let spiderMan = LandCategory(
        id: "sld-spiderman",
        name: "Secret Lair x Spider-Man",
        iconName: "web.camera.fill",
        description: "Marvel's Spider-Man: Mana Symbiote (2025) by Pedro Potier. Raised foil, inverted frame. Universes Beyond. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1950", "1951", "1952", "1953", "1954"]
    )

    // MARK: - KEXP Lands

    static let kexp = LandCategory(
        id: "sld-kexp",
        name: "KEXP: Where the Music Matters",
        iconName: "radio.fill",
        description: "KEXP radio station collaboration (2025) by Dan Black and Jessica Seamans. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["2076", "2077", "2078", "2079", "2080"]
    )

    // MARK: - D&D: Lands of the Forgotten Realms

    static let dndLands = LandCategory(
        id: "sld-dnd",
        name: "D&D: Forgotten Realms Lands",
        iconName: "shield.fill",
        description: "Dungeons & Dragons: Lands of the Forgotten Realms (2026) by Arthur Yuan. Sources: Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["2509", "2510", "2511", "2512", "2513"]
    )

    // MARK: - Artist Series: Alayna Danner

    static let alanynaDannerArtist = LandCategory(
        id: "sld-alayna-danner",
        name: "Artist Series: Alayna Danner",
        iconName: "paintbrush.fill",
        description: "Full-art basics by Alayna Danner (2024). Three lands: Plains, Mountain, Forest. Sources: Scryfall.",
        cardNames: ["Plains", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1513", "1514", "1515"]
    )

    // MARK: - The Mountain Goats

    static let mountainGoats = LandCategory(
        id: "sld-mountain-goats",
        name: "The Mountain Goats",
        iconName: "music.note.list",
        description: "10 Mountains with Lorwyn flavor text by John Darnielle (2023). Art by 10 different artists including Fred Fields and Ron Spears. Sources: Scryfall.",
        cardNames: ["Mountain"],
        setCodes: ["sld"],
        collectorNumbers: ["1358", "1359", "1360", "1361", "1362", "1363", "1364", "1365", "1366", "1367"]
    )

    // MARK: - Special Guest: Kelogsloops

    static let kelogsloops = LandCategory(
        id: "sld-kelogsloops",
        name: "Special Guest: Kelogsloops",
        iconName: "drop.fill",
        description: "4 Island variants by Kelogsloops (2025). Inverted frame. Watercolor dreamscape style. Sources: Scryfall.",
        cardNames: ["Island"],
        setCodes: ["sld"],
        collectorNumbers: ["2144", "2145", "2146", "2147"]
    )
}
