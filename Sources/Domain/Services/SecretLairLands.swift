import Foundation

// MARK: - Secret Lair Lands

/// Individual Secret Lair basic-land drops, each with its own collector-number
/// range so only that drop's printings are resolved from the shared "sld" set code.
enum SecretLairLands {

    static let all: [LandCategory] = [
        tokyoLands,
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
    ]

    // MARK: - The Tokyo Lands

    static let tokyoLands = LandCategory(
        id: "sld-tokyo",
        name: "The Tokyo Lands",
        iconName: "building.2.fill",
        description: "Tokyo cityscapes by Jeanne D'Angelo (2022). The most sought-after Secret Lair basics (~$75/card). City of Tokyo settings with distinctive Japanese aesthetic. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["384", "385", "386", "387", "388"]
    )

    // MARK: - Special Guest: Kozyndan

    static let kozyndan = LandCategory(
        id: "sld-kozyndan",
        name: "Special Guest: Kozyndan",
        iconName: "paintbrush.pointed.fill",
        description: "Japanese-influenced art by married artist duo kozyndan (2022). Calm, serene visual style with striking compositions. Second most valuable Secret Lair basics (~$59/card). Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1130", "1131", "1132", "1133", "1134"]
    )

    // MARK: - PixelSnowLands (Paradise Frost)

    static let pixelSnowLands = LandCategory(
        id: "sld-pixel-snow",
        name: "PixelSnowLands.jpg",
        iconName: "snowflake",
        description: "Pixel art snow-covered basics by Jubilee (2021). Retro Windows-era video game aesthetic. Third most valuable Secret Lair basics (~$59/card). Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp", "Snow-Covered Mountain", "Snow-Covered Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["325", "326", "327", "328", "329"]
    )

    // MARK: - The Godzilla Lands

    static let godzillaLands = LandCategory(
        id: "sld-godzilla",
        name: "The Godzilla Lands",
        iconName: "flame.fill",
        description: "Godzilla/kaiju IP crossover lands (2022). Art by Roberto Gatto, Alexander Kintner, and Kevin Gnutzmans. Among the first external IP basic lands in MTG. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["448", "449", "450", "451", "452"]
    )

    // MARK: - The Unfathomable Crushing Brutality of Basic Lands

    static let unfathomableCrushingBrutality = LandCategory(
        id: "sld-brutality",
        name: "Unfathomable Crushing Brutality",
        iconName: "bolt.fill",
        description: "Dark, metal/goth-inspired basic lands (2020). Art by Rosemary Valero-O'Connell, Andy Williams, Mr. Misang, Yuumei, Nicole Gustafsson, and Marija Tiurina. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["46", "47", "48", "49", "50"]
    )

    // MARK: - Transformers

    static let transformers = LandCategory(
        id: "sld-transformers",
        name: "Transformers Lands",
        iconName: "gearshape.fill",
        description: "Transformers IP crossover lands (2022). Universes Beyond release featuring iconic Transformers landscapes. Popular with 80s nostalgia collectors. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["670", "671", "672", "673", "674"]
    )

    // MARK: - Featuring: Gary Baseman

    static let garyBaseman = LandCategory(
        id: "sld-baseman",
        name: "Featuring: Gary Baseman",
        iconName: "theatermasks.fill",
        description: "Surreal cartoon art by Gary Baseman (2023), known for Cranium board game and Teacher's Pet. Uniquely weird and whimsical basic lands. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1382", "1383", "1384", "1385", "1386"]
    )

    // MARK: - Shades Not Included

    static let shadesNotIncluded = LandCategory(
        id: "sld-shades",
        name: "Shades Not Included",
        iconName: "sun.max.fill",
        description: "Synthwave/retrowave neon basics by Ben Schnuck (2022). Artist is a beloved proxy artist in the MTG community. Vibrant neon aesthetic. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["415", "416", "417", "418", "419"]
    )

    // MARK: - Secret Lair x Arcane

    static let arcane = LandCategory(
        id: "sld-arcane",
        name: "Secret Lair x Arcane",
        iconName: "sparkle",
        description: "League of Legends / Arcane Netflix series crossover (2021). Universes Beyond. Features locations from the animated series. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["484", "485", "486", "487", "488"]
    )

    // MARK: - Secret Lair x Post Malone

    static let postMalone = LandCategory(
        id: "sld-post-malone",
        name: "Secret Lair x Post Malone",
        iconName: "music.note",
        description: "Post Malone collaboration (2022) featuring classic MTG artists Mark Poole, Fred Fields, Ron Spears, Donato Giancola, and Drew Tucker. Nostalgic old-school art style. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1190", "1191", "1192", "1193", "1194"]
    )

    // MARK: - PixelLands_v02.jpg

    static let pixelLandsV2 = LandCategory(
        id: "sld-pixel-v2",
        name: "PixelLands_v02.jpg",
        iconName: "square.grid.3x3.fill",
        description: "Pixel art regular basics by Jubilee (2023). Sequel to the hugely popular PixelSnowLands, this time with non-snow basics in the same retro pixel style. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1468", "1469", "1470", "1471", "1472"]
    )

    // MARK: - Featuring: JungShan

    static let jungShan = LandCategory(
        id: "sld-jungshan",
        name: "Featuring: JungShan",
        iconName: "mountain.2.fill",
        description: "East Asian watercolor/ink painting style basics by JungShan (2023). Dramatic, sweeping traditional Asian landscapes. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1399", "1400", "1401", "1402", "1403"]
    )

    // MARK: - The Full-Text Lands

    static let fullTextLands = LandCategory(
        id: "sld-full-text",
        name: "The Full-Text Lands",
        iconName: "text.justify.left",
        description: "Novelty lands with massive text boxes exhaustively explaining how basic lands work (2022). A humorous take on Magic's rules text. Art by Kamila Szutenberg. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Plains", "Island", "Swamp", "Mountain", "Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["346", "347", "348", "349", "350"]
    )

    // MARK: - Eldraine Wonderland

    static let eldraineWonderland = LandCategory(
        id: "sld-eldraine",
        name: "Eldraine Wonderland",
        iconName: "wand.and.stars",
        description: "Snow-covered basics by Alayna Danner (2019). Among the very first Secret Lair drops. Fairy tale winter landscapes inspired by Throne of Eldraine. Sources: CoolStuffInc, Scryfall.",
        cardNames: ["Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp", "Snow-Covered Mountain", "Snow-Covered Forest"],
        setCodes: ["sld"],
        collectorNumbers: ["1", "2", "3", "4", "5"]
    )
}
