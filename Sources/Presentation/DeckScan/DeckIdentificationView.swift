import SwiftUI

// MARK: - Deck Identification View

/// Displays deck identification results, showing matched archetypes
/// grouped by format with match percentages and card lists.
struct DeckIdentificationView: View {

    let result: DeckIdentificationResult

    @State private var expandedMatchIDs: Set<UUID> = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            headerSection

            if result.matches.isEmpty {
                emptyStateSection
            } else {
                matchesSection
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Deck Identification")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(result.totalCardsAnalyzed) unique cards analyzed")
                .font(MD3Typography.bodySmall)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        MD3Card {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)

                Text("Could not determine deck archetype. Try scanning more cards.")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Matches

    private var matchesSection: some View {
        let topMatches = Array(result.matches.prefix(5))
        return ForEach(topMatches) { match in
            matchCard(for: match)
        }
    }

    private func matchCard(for match: DeckMatch) -> some View {
        let isExpanded = expandedMatchIDs.contains(match.id)

        return MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                // Archetype name + format badge
                HStack {
                    Text(match.archetype)
                        .font(MD3Typography.headlineSmall)
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)

                    Spacer()

                    Text(match.format)
                        .font(MD3Typography.labelMedium)
                        .foregroundStyle(MD3Theme.onPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(MD3Theme.primary)
                        .clipShape(Capsule())
                }

                // Match percentage bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(format: "%.0f%% match", match.matchPercentage))
                            .font(MD3Typography.titleSmall)
                            .foregroundStyle(MD3Theme.primary)

                        Spacer()

                        Text("\(match.matchedCards.count) of \(result.totalCardsAnalyzed) cards matched")
                            .font(MD3Typography.labelMedium)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(MD3Theme.surfaceVariant)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(MD3Theme.primary)
                                .frame(
                                    width: geometry.size.width * min(match.matchPercentage / 100.0, 1.0),
                                    height: 8
                                )
                        }
                    }
                    .frame(height: 8)
                }

                // Expandable card list
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedMatchIDs.remove(match.id)
                        } else {
                            expandedMatchIDs.insert(match.id)
                        }
                    }
                } label: {
                    HStack {
                        Text(isExpanded ? "Hide matched cards" : "Show matched cards")
                            .font(MD3Typography.labelLarge)
                            .foregroundStyle(MD3Theme.primary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(MD3Theme.primary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()

                    ForEach(match.matchedCards, id: \.self) { cardName in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(MD3Theme.primary)

                            Text(cardName)
                                .font(MD3Typography.bodyMedium)
                                .foregroundStyle(MD3Theme.onSurface)
                        }
                    }
                }

                // MTGTop8 link
                Divider()

                Button {
                    let encoded = match.archetype.replacingOccurrences(of: " ", with: "+")
                    let urlString = "https://mtgtop8.com/archetype?a=\(encoded)&meta=\(mtgTop8FormatCode(match.format))"
                    if let url = URL(string: urlString) {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "globe")
                            .font(.caption)
                        Text("View on MTGTop8")
                            .font(MD3Typography.labelLarge)
                    }
                    .foregroundStyle(MD3Theme.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func mtgTop8FormatCode(_ format: String) -> String {
        let codes: [String: String] = [
            "Standard": "ST",
            "Pioneer": "PI",
            "Modern": "MO",
            "Legacy": "LE",
            "Vintage": "VI",
            "Pauper": "PAU",
            "Premodern": "PREM",
        ]
        return codes[format] ?? ""
    }
}
