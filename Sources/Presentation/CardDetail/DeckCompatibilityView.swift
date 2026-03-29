import SwiftUI

// MARK: - Deck Compatibility View

/// Displays deck compatibility information for a card, including
/// EDHREC commander data, MTGTop8 tournament data, and external links.
struct DeckCompatibilityView: View {

    let card: Card
    let edhrecService: EDHRECServiceProtocol
    let mtgTop8Service: MTGTop8ServiceProtocol

    @State private var edhrecData: EDHRECCardData?
    @State private var isLoadingEDHREC = false
    @State private var mtgTop8Data: MTGTop8CardData?
    @State private var isLoadingTop8 = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            commanderPopularitySection
            commanderDecksSection
            tournamentPlaySection
            externalLinksSection
        }
        .task {
            await loadEDHRECData()
        }
        .task {
            await loadMTGTop8Data()
        }
    }

    // MARK: - Section 1: Commander Popularity (offline)

    @ViewBuilder
    private var commanderPopularitySection: some View {
        if let rank = card.edhrecRank {
            MD3Card {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(MD3Theme.tertiary)

                    Text("Commander Rank: #\(rank)")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    Spacer()
                }
                .padding(16)
            }
        }
    }

    // MARK: - Section 2: Commander Decks (on-demand)

    @ViewBuilder
    private var commanderDecksSection: some View {
        if isLoadingEDHREC {
            MD3Card {
                HStack {
                    ProgressView()
                    Text("Loading commander data...")
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .padding(.leading, 8)
                    Spacer()
                }
                .padding(16)
            }
        } else if let data = edhrecData {
            MD3Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Commander Decks")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    Text("Used in \(data.numDecks) of \(data.potentialDecks) Commander decks (\(String(format: "%.0f", data.inclusionPercent))%)")
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)

                    if !data.topCommanders.isEmpty {
                        Divider()

                        Text("Top Commanders")
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)

                        ForEach(Array(data.topCommanders.prefix(5))) { commander in
                            HStack {
                                Text(commander.name)
                                    .font(MD3Typography.bodyMedium)
                                    .foregroundStyle(MD3Theme.onSurface)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(String(format: "%.0f", commander.inclusionPercent))%")
                                    .font(MD3Typography.labelMedium)
                                    .foregroundStyle(MD3Theme.primary)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Section 3: Tournament Play (on-demand)

    @ViewBuilder
    private var tournamentPlaySection: some View {
        if isLoadingTop8 {
            MD3Card {
                HStack {
                    ProgressView()
                    Text("Loading tournament data...")
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .padding(.leading, 8)
                    Spacer()
                }
                .padding(16)
            }
        } else if let data = mtgTop8Data {
            MD3Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tournament Play")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    Text("Found in \(data.totalDecks) tournament decks")
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)

                    if !data.topArchetypes.isEmpty {
                        Divider()

                        Text("Top Archetypes")
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)

                        ForEach(Array(data.topArchetypes.prefix(5))) { archetype in
                            HStack {
                                Text(archetype.name)
                                    .font(MD3Typography.bodyMedium)
                                    .foregroundStyle(MD3Theme.onSurface)
                                    .lineLimit(1)

                                Spacer()

                                Text(archetype.format)
                                    .font(MD3Typography.labelSmall)
                                    .foregroundStyle(MD3Theme.onSurfaceVariant)

                                Text("\(archetype.count)")
                                    .font(MD3Typography.labelMedium)
                                    .foregroundStyle(MD3Theme.primary)
                                    .frame(minWidth: 30, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Section 4: External Links

    private var externalLinksSection: some View {
        MD3Card {
            VStack(spacing: 12) {
                Text("External Resources")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)

                MD3OutlinedButton("View on EDHREC") {
                    let encoded = card.name
                        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? card.name
                    if let url = URL(string: "https://edhrec.com/route/?cc=\(encoded)") {
                        openURL(url)
                    }
                }

                MD3OutlinedButton("View on MTGTop8") {
                    let urlString: String
                    if let data = mtgTop8Data {
                        urlString = data.searchURL
                    } else {
                        let encoded = card.name.replacingOccurrences(of: " ", with: "+")
                        urlString = "https://mtgtop8.com/search?MD_check=1&SB_check=1&cards=\(encoded)"
                    }
                    if let url = URL(string: urlString) {
                        openURL(url)
                    }
                }

                MD3OutlinedButton("MTGGoldfish Metagame") {
                    let format: String
                    if card.legalities.isLegal(in: "standard") {
                        format = "standard"
                    } else if card.legalities.isLegal(in: "pioneer") {
                        format = "pioneer"
                    } else if card.legalities.isLegal(in: "modern") {
                        format = "modern"
                    } else if card.legalities.isLegal(in: "legacy") {
                        format = "legacy"
                    } else {
                        format = "commander"
                    }
                    if let url = URL(string: "https://www.mtggoldfish.com/metagame/\(format)") {
                        openURL(url)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Data Loading

    private func loadEDHRECData() async {
        isLoadingEDHREC = true
        defer { isLoadingEDHREC = false }

        do {
            edhrecData = try await edhrecService.fetchCardData(name: card.name)
        } catch {
            // Fail gracefully - don't show anything
            edhrecData = nil
        }
    }

    private func loadMTGTop8Data() async {
        isLoadingTop8 = true
        defer { isLoadingTop8 = false }

        do {
            mtgTop8Data = try await mtgTop8Service.fetchCardData(name: card.name)
        } catch {
            // Fail gracefully - don't show anything
            mtgTop8Data = nil
        }
    }
}
