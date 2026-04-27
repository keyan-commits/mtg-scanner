import SwiftUI

/// Shared PH Stores section showing tcgph.com listings for a card.
/// Used in CardDetailView and CardCopiesDetailView.
struct PHStoresSection: View {
    let cardName: String
    let listings: [TCGPHListing]
    let isLoading: Bool
    /// Direct tcgph.com URL for this card (if available from API response).
    let tcgphURL: String?

    var body: some View {
        if isLoading {
            loadingState
        } else if !listings.isEmpty {
            listingsState
        } else {
            emptyState
        }
    }

    // MARK: - States

    private var loadingState: some View {
        MD3Card {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Checking PH stores\u{2026}")
                    .font(MD3Typography.bodySmall)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var listingsState: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("PH Stores")
                        .font(MD3Typography.titleMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                    Spacer()
                    Text("\(listings.count) listing\(listings.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }

                ForEach(listings) { listing in
                    listingRow(listing)
                    if listing.id != listings.last?.id {
                        Divider()
                    }
                }

                storeLinks
                    .padding(.vertical, 4)

                Text("Prices in PHP from tcgph.com (17 PH stores)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        MD3Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("PH Stores")
                    .font(MD3Typography.titleMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Text("No listings found on tcgph.com")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                storeLinks
            }
            .padding(16)
        }
    }

    // MARK: - Subviews

    private func listingRow(_ listing: TCGPHListing) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.storeName)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(listing.condition)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ConditionFormatter.color(listing.condition))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(ConditionFormatter.color(listing.condition).opacity(0.15))
                        .clipShape(Capsule())
                    if listing.quantity > 1 {
                        Text("\(listing.quantity) avail")
                            .font(.caption2)
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
            }
            Spacer()
            Text("\u{20B1}\(String(format: "%.0f", listing.price))")
                .font(MD3Typography.titleMedium)
                .foregroundStyle(MD3Theme.primary)
                .monospacedDigit()
            if let url = URL(string: listing.storeURL) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.primary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var storeLinks: some View {
        HStack(spacing: 16) {
            if let tcgphURL, let url = URL(string: tcgphURL) {
                tcgphLink(url: url)
            } else {
                let slug = cardName.toTCGPHSlug()
                if let url = URL(string: "https://tcgph.com/card/\(slug)") {
                    tcgphLink(url: url)
                }
            }
            Spacer()
            if let url = cardName.toMTGTambayURL() {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.3.fill").font(.caption)
                        Text("MTG Tambayan")
                    }
                    .font(MD3Typography.labelLarge)
                    .foregroundStyle(.blue)
                }
            }
        }
    }

    private func tcgphLink(url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.caption)
                Text("tcgph.com")
            }
            .font(MD3Typography.labelLarge)
            .foregroundStyle(MD3Theme.primary)
        }
    }
}
