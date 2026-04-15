import SwiftUI

/// Read-only view that displays a saved card-list analysis.
/// Shows the format breakdown with legal/illegal cards for each format,
/// matching the visual style of the DeckBuilderScreen results.
/// Supports fetching competitive reference decklists from MTGTop8.
struct CardAnalysisDetailView: View {

    let analysis: CardAnalysis
    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol?

    @State private var results: [AnalysisFormatResult] = []
    @State private var showRawList = false
    @State private var isCreatingDeck = false
    @State private var createdDeck: DeckList?

    // Reference decklist state (keyed by AnalysisFormatResult.id which is the format string)
    @State private var referenceDecklists: [String: MTGTop8Decklist] = [:]
    @State private var fetchingReferenceFor: String?
    @State private var referenceError: [String: String] = [:]

    private let mtgTop8Service: MTGTop8ServiceProtocol = MTGTop8Service()
    private let archetypeIndex = MTGTop8ArchetypeIndex()

    var body: some View {
        Group {
            if let deck = createdDeck {
                DeckDetailView(
                    deck: deck,
                    repository: deckRepository,
                    cardRepository: cardRepository
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection

                        ForEach(results) { result in
                            formatCard(result)
                        }

                        rawCardListSection
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(createdDeck != nil ? "" : analysis.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            results = analysis.formatResults
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(MD3Theme.primary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.title)
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onBackground)
                    Text(analysis.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
            if !results.isEmpty {
                let best = results[0]
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Best match: \(best.suggestedDeckName) (\(Int(best.percentage))%)")
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
        }
    }

    // MARK: - Format Card

    private func formatCard(_ result: AnalysisFormatResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(result.suggestedDeckName)
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Spacer()
                Text("\(Int(result.percentage))%")
                    .font(MD3Typography.titleLarge)
                    .foregroundStyle(percentageColor(result.percentage))
                    .monospacedDigit()
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MD3Theme.surfaceVariant)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(percentageColor(result.percentage))
                        .frame(width: geo.size.width * min(result.percentage / 100.0, 1.0), height: 8)
                }
            }
            .frame(height: 8)

            if let urlString = result.referenceURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("View reference decklist")
                    }
                    .font(.caption)
                    .foregroundStyle(MD3Theme.primary)
                }
            }

            // Reference decklist fetch section
            if result.archetypeName != nil {
                referenceDeckSection(result)
            }

            // Stats
            HStack(spacing: 16) {
                statLabel(
                    "\(result.totalLegalQuantity) legal",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                statLabel(
                    "\(result.illegalCards.reduce(0) { $0 + $1.quantity }) illegal",
                    icon: "xmark.circle.fill",
                    color: MD3Theme.error
                )
                Spacer()
                Text("of \(result.deckSize)-card deck")
                    .font(MD3Typography.labelSmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

            // Legal cards
            if !result.legalCards.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(result.legalCards) { card in
                            HStack(spacing: 4) {
                                Text("\(card.quantity)x")
                                    .font(MD3Typography.labelSmall)
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                                    .monospacedDigit()
                                    .frame(width: 24, alignment: .trailing)
                                Text(card.name)
                                    .font(MD3Typography.bodySmall)
                                    .foregroundStyle(.green)
                                    .lineLimit(1)
                                if let setCode = card.setCode {
                                    Text("[\(setCode.uppercased())]")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Legal cards (\(result.legalCards.count))")
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                    }
                }
            }

            // Build Deck button
            if let refDeck = referenceDecklists[result.id], cardRepository != nil {
                MD3FilledButton("Build Full \(result.displayName) Deck") {
                    Task { await createDeckFromReference(result: result, reference: refDeck) }
                }
                .disabled(isCreatingDeck)
            } else if result.totalLegalQuantity >= 10, cardRepository != nil {
                MD3FilledButton("Build \(result.displayName) Deck") {
                    Task { await buildDeck(from: result) }
                }
                .disabled(isCreatingDeck)
            }

            // Illegal cards
            if !result.illegalCards.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(result.illegalCards) { card in
                            HStack(spacing: 4) {
                                Text("\(card.quantity)x")
                                    .font(MD3Typography.labelSmall)
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                                    .monospacedDigit()
                                    .frame(width: 24, alignment: .trailing)
                                Text(card.name)
                                    .font(MD3Typography.bodySmall)
                                    .foregroundStyle(MD3Theme.error)
                                    .lineLimit(1)
                                if let reason = card.reason {
                                    Text("(\(reason))")
                                        .font(.system(.caption2))
                                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.error)
                        Text("Illegal cards (\(result.illegalCards.count))")
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(MD3Theme.onSurface)
                    }
                }
            }
        }
        .padding(16)
        .background(MD3Theme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Raw Card List

    private var rawCardListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showRawList.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showRawList ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Original Card List")
                        .font(MD3Typography.labelMedium)
                }
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

            if showRawList {
                Text(analysis.rawCardList)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MD3Theme.surfaceVariant.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Build Deck

    private func buildDeck(from result: AnalysisFormatResult) async {
        guard let cardRepository else { return }
        isCreatingDeck = true
        defer { isCreatingDeck = false }

        let format = DeckFormat(rawValue: result.format) ?? .freeform
        let formatStored = format == .freeform ? nil : format.rawValue
        guard let deck = try? deckRepository.createDeck(
            name: result.suggestedDeckName,
            format: formatStored
        ) else { return }

        deck.referenceURL = result.referenceURL

        let isCommander = format == .commander
        let basicLands: Set<String> = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"]

        for analysisCard in result.legalCards {
            // Resolve the card from the database to get a full Card object
            let resolved = await resolveCard(name: analysisCard.name, setCode: analysisCard.setCode, using: cardRepository)
            guard let card = resolved else { continue }

            let qty: Int
            if isCommander && !basicLands.contains(card.name) {
                qty = 1
            } else {
                qty = analysisCard.quantity
            }

            if let item = try? deckRepository.addItem(card: card, quantity: qty, to: deck) {
                item.statusRaw = "arrived"
            }
        }

        createdDeck = deck
    }

    private func resolveCard(name: String, setCode: String?, using repo: CardRepositoryProtocol) async -> Card? {
        if let setCode {
            let variants = (try? await repo.findVariants(name: name, setCode: setCode)) ?? []
            if let first = variants.first { return first }
        }
        let printings = (try? await repo.findAllPrintings(name: name)) ?? []
        if let first = printings.first { return first }
        if let card = try? await repo.identifyCard(name: name) {
            return card
        }
        return try? await repo.findFuzzyMatch(name: name)
    }

    // MARK: - Reference Decklist

    /// Button + view for fetching and displaying a reference decklist.
    @ViewBuilder
    private func referenceDeckSection(_ result: AnalysisFormatResult) -> some View {
        let isFetching = fetchingReferenceFor == result.id

        if let refDeck = referenceDecklists[result.id] {
            referenceDeckComparisonView(result: result, reference: refDeck)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { await fetchReferenceDecklist(for: result) }
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

                if let error = referenceError[result.id] {
                    Text(error)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(MD3Theme.error)
                }
            }
        }
    }

    /// Fetches the top competitive decklist for an analysis result's archetype.
    private func fetchReferenceDecklist(for result: AnalysisFormatResult) async {
        guard let archetypeName = result.archetypeName else {
            referenceError[result.id] = "No archetype identified for this format"
            return
        }

        fetchingReferenceFor = result.id
        referenceError[result.id] = nil
        defer { fetchingReferenceFor = nil }

        let formatCode = mtgTop8FormatCode(for: result.format)
        guard let mtgFormat = MTGTop8Format(rawValue: formatCode) else {
            referenceError[result.id] = "Unsupported format: \(result.displayName)"
            return
        }

        do {
            let matches = try await archetypeIndex.search(archetypeName, in: [mtgFormat], limit: 1)

            var archetypeID: String
            if let matched = matches.first {
                archetypeID = String(matched.archetypeID)
            } else if let refURL = result.referenceURL,
                      let range = refURL.range(of: "a=") {
                let afterA = refURL[range.upperBound...]
                let idStr = String(afterA.prefix(while: { $0.isNumber }))
                if !idStr.isEmpty {
                    archetypeID = idStr
                    print("[CardAnalysisDetail] Dynamic search failed, using hardcoded archetype ID \(idStr) from URL")
                } else {
                    referenceError[result.id] = "Archetype '\(archetypeName)' not found on MTGTop8 for \(result.displayName)"
                    return
                }
            } else {
                referenceError[result.id] = "Archetype '\(archetypeName)' not found on MTGTop8 for \(result.displayName)"
                return
            }

            guard let topDeck = try await mtgTop8Service.fetchMostRecentDeck(
                archetypeID: archetypeID,
                format: formatCode
            ) else {
                referenceError[result.id] = "No decks found for \(archetypeName)"
                return
            }

            let decklist = try await mtgTop8Service.fetchDecklist(deckID: topDeck.deckID)

            if decklist.mainboard.isEmpty {
                referenceError[result.id] = "Empty decklist returned"
                return
            }

            referenceDecklists[result.id] = decklist
        } catch {
            referenceError[result.id] = "Failed to fetch: \(error.localizedDescription)"
        }
    }

    /// Displays the full reference decklist with owned/missing markers.
    private func referenceDeckComparisonView(result: AnalysisFormatResult, reference: MTGTop8Decklist) -> some View {
        let userCardNames = buildUserCardNameSet(from: result)
        let mainboardTotal = reference.mainboard.reduce(0) { $0 + $1.quantity }
        let sideboardTotal = reference.sideboard.reduce(0) { $0 + $1.quantity }
        let mainboardOwned = reference.mainboard.reduce(0) { total, entry in
            total + (userCardNames[entry.cardName.lowercased()] != nil ? min(entry.quantity, userCardNames[entry.cardName.lowercased()]!) : 0)
        }
        let sideboardOwned = reference.sideboard.reduce(0) { total, entry in
            total + (userCardNames[entry.cardName.lowercased()] != nil ? min(entry.quantity, userCardNames[entry.cardName.lowercased()]!) : 0)
        }

        return VStack(alignment: .leading, spacing: 10) {
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
                let key = entry.cardName.lowercased()
                let owned = userCards[key] ?? 0
                let hasEnough = owned >= entry.quantity

                HStack(spacing: 6) {
                    Image(systemName: hasEnough ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(hasEnough ? .green : MD3Theme.error)

                    Text("\(entry.quantity)")
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .monospacedDigit()
                        .frame(width: 16, alignment: .trailing)

                    Text(entry.cardName)
                        .font(MD3Typography.bodySmall)
                        .foregroundStyle(hasEnough ? MD3Theme.onSurface : MD3Theme.onSurfaceVariant)
                        .lineLimit(1)

                    Spacer()

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

    /// Builds a `[lowercased card name: total quantity]` map from the analysis result's legal cards.
    private func buildUserCardNameSet(from result: AnalysisFormatResult) -> [String: Int] {
        var map: [String: Int] = [:]
        for card in result.legalCards {
            let key = card.name.lowercased()
            map[key, default: 0] += card.quantity
        }
        return map
    }

    /// Maps a DeckFormat rawValue string to the MTGTop8 format code.
    private func mtgTop8FormatCode(for format: String) -> String {
        switch format {
        case "modern":    return "MO"
        case "legacy":    return "LE"
        case "vintage":   return "VI"
        case "standard":  return "ST"
        case "pioneer":   return "PI"
        case "pauper":    return "PAU"
        case "commander": return "EDH"
        case "premodern": return "PREM"
        default:          return "MO"
        }
    }

    /// Creates a deck from the FULL reference decklist. Cards the user owns
    /// are marked "Arrived", missing cards are marked "Needed".
    private func createDeckFromReference(result: AnalysisFormatResult, reference: MTGTop8Decklist) async {
        guard let cardRepository else { return }
        isCreatingDeck = true
        defer { isCreatingDeck = false }

        let format = DeckFormat(rawValue: result.format) ?? .freeform
        let formatStored = format == .freeform ? nil : format.rawValue
        guard let deck = try? deckRepository.createDeck(
            name: result.suggestedDeckName,
            format: formatStored
        ) else { return }

        deck.referenceURL = result.referenceURL

        let userCards = buildUserCardNameSet(from: result)
        let isCommander = format == .commander
        let basicLands: Set<String> = ["Plains", "Island", "Swamp", "Mountain", "Forest", "Wastes"]

        let allEntries: [(entry: MTGTop8DecklistEntry, zone: String)] =
            reference.mainboard.map { ($0, "mainboard") } +
            reference.sideboard.map { ($0, "sideboard") }

        for (entry, zone) in allEntries {
            let key = entry.cardName.lowercased()
            let qty = (isCommander && !basicLands.contains(entry.cardName)) ? min(entry.quantity, 1) : entry.quantity
            let ownedQty = userCards[key] ?? 0
            let hasEnough = ownedQty >= qty

            let resolved = await resolveCard(name: entry.cardName, setCode: nil, using: cardRepository)

            if let card = resolved {
                if let item = try? deckRepository.addItem(card: card, quantity: qty, to: deck, zone: zone) {
                    item.statusRaw = hasEnough ? "arrived" : "needed"
                    let allItems = deck.items.filter { $0.cardName == card.name }
                    for deckItem in allItems.suffix(qty) {
                        deckItem.statusRaw = hasEnough ? "arrived" : "needed"
                    }
                }
            } else {
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

    // MARK: - Helpers

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
}
