import SwiftUI

// MARK: - Deck Compatibility View

/// Displays deck archetypes grouped by format, commander data,
/// and external links for a Magic card.
struct DeckCompatibilityView: View {

    let card: Card
    let deckLookupService: DeckLookupServiceProtocol

    @State private var result: DeckLookupResult?
    @State private var isLoading: Bool = true

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                loadingSection
            } else if let result {
                headerSection
                formatSections(result.formatResults)
                externalLinksSection
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Text("Deck Archetypes")
            .font(MD3Typography.titleLarge)
            .foregroundStyle(MD3Theme.onBackground)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading

    private var loadingSection: some View {
        MD3Card {
            HStack {
                ProgressView()
                Text("Loading deck data...")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .padding(.leading, 8)
                Spacer()
            }
            .padding(16)
        }
    }

    // MARK: - Format Sections

    @ViewBuilder
    private func formatSections(_ formatResults: [FormatDeckData]) -> some View {
        let legalFormats = formatResults.filter(\.isLegal)
        ForEach(legalFormats) { formatData in
            formatCard(for: formatData)
        }
    }

    private func formatCard(for formatData: FormatDeckData) -> some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(formatData.format)
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)

                    Spacer()

                    Text("\(formatData.totalDecks) decks")
                        .font(MD3Typography.labelMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }

                if formatData.archetypes.isEmpty {
                    Text("No tournament data")
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                } else {
                    let topArchetypes = Array(formatData.archetypes.prefix(5))
                    let maxCount = topArchetypes.map(\.count).max() ?? 1

                    Divider()

                    ForEach(topArchetypes) { archetype in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(archetype.name)
                                    .font(MD3Typography.titleSmall)
                                    .foregroundStyle(MD3Theme.onSurface)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(archetype.count)")
                                    .font(MD3Typography.labelMedium)
                                    .foregroundStyle(MD3Theme.onPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                    .background(MD3Theme.primary)
                                    .clipShape(Capsule())
                            }

                            GeometryReader { geometry in
                                let fraction = CGFloat(archetype.count) / CGFloat(maxCount)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(MD3Theme.primary.opacity(0.35))
                                    .frame(width: geometry.size.width * fraction, height: 6)
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Commander Section

    @ViewBuilder
    private func commanderSection(_ commanderData: EDHRECCardData?) -> some View {
        if let data = commanderData {
            MD3Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Commander")
                            .font(MD3Typography.titleMedium)
                            .foregroundStyle(MD3Theme.onSurface)

                        Spacer()

                        Text("Used in \(data.numDecks) decks")
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }

                    if !data.topCommanders.isEmpty {
                        Divider()

                        let topCommanders = Array(data.topCommanders.prefix(5))

                        ForEach(topCommanders) { commander in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(commander.name)
                                        .font(MD3Typography.titleSmall)
                                        .foregroundStyle(MD3Theme.onSurface)
                                        .lineLimit(1)

                                    Spacer()

                                    Text("\(String(format: "%.0f", commander.inclusionPercent))%")
                                        .font(MD3Typography.labelMedium)
                                        .foregroundStyle(MD3Theme.onTertiary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 3)
                                        .background(MD3Theme.tertiary)
                                        .clipShape(Capsule())
                                }

                                GeometryReader { geometry in
                                    let fraction = CGFloat(commander.inclusionPercent) / 100.0
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(MD3Theme.tertiary.opacity(0.35))
                                        .frame(width: geometry.size.width * fraction, height: 6)
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - EDHREC Rank Badge

    @ViewBuilder
    private var edhrecRankBadge: some View {
        if let rank = card.edhrecRank {
            HStack {
                Text("EDHREC Rank #\(rank)")
                    .font(MD3Typography.labelMedium)
                    .foregroundStyle(MD3Theme.onTertiaryContainer)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(MD3Theme.tertiaryContainer)
                    .clipShape(Capsule())

                Spacer()
            }
        }
    }

    // MARK: - External Links

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
                    let encoded = card.name.replacingOccurrences(of: " ", with: "+")
                    let urlString = "https://mtgtop8.com/search?MD_check=1&SB_check=1&cards=\(encoded)"
                    if let url = URL(string: urlString) {
                        openURL(url)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        do {
            result = await deckLookupService.lookupDecks(for: card)
        } catch {
            result = nil
        }
        isLoading = false
    }
}
