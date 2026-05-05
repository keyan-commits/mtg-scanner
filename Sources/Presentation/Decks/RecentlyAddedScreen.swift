import SwiftUI

/// Summary of cards recently added to the user's collection — anything
/// that landed via batch scan, manual add, or a marked-arrived order shows
/// up here, sorted newest-first and bucketed by relative date so the user
/// can scan back through their recent imports at a glance.
struct RecentlyAddedScreen: View {

    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol

    @State private var items: [CollectionItem] = []
    @State private var resolvedCards: [String: Card] = [:]
    @Bindable private var currencyService = CurrencyService.shared

    /// Bucket relative to "now" — order matters; first match wins.
    private enum Bucket: Int, CaseIterable {
        case today, yesterday, lastWeek, lastMonth, earlier

        var title: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .lastWeek: return "Earlier this week"
            case .lastMonth: return "Earlier this month"
            case .earlier: return "Older"
            }
        }
    }

    private struct Batch: Identifiable {
        /// Timestamp of the most-recent item in the batch (used for ID + display).
        let timestamp: Date
        let items: [CollectionItem]
        var id: Double { timestamp.timeIntervalSince1970 }
    }

    private struct Section: Identifiable {
        let bucket: Bucket
        let batches: [Batch]
        var id: Int { bucket.rawValue }
    }

    /// Items added within this many seconds of each other are treated
    /// as one batch. 5 minutes covers a multi-photo batch scan +
    /// follow-up corrections without merging genuinely separate
    /// sessions.
    private static let batchWindowSeconds: TimeInterval = 300

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                listBody
            }
        }
        .navigationTitle("Recently Added")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .task { await currencyService.refreshIfStale() }
    }

    // MARK: - Body

    private var listBody: some View {
        // Summary tile lives OUTSIDE the List so it's always pinned at
        // the top of the screen — putting it in a List section caused
        // it to scroll away the moment the user opened the screen.
        VStack(spacing: 0) {
            summaryHeader
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            List {
                ForEach(sections) { section in
                    SwiftUI.Section(section.bucket.title) {
                        ForEach(section.batches) { batch in
                            batchHeader(batch)
                            ForEach(batch.items) { item in
                                NavigationLink {
                                    cardDetailDestination(for: item)
                                } label: {
                                    row(item)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Per-batch subtotal: cards added within ~5 minutes of each
    /// other render as a single batch with this header showing total
    /// value + copy count. Answers the user's "I want to see the
    /// total of THIS scan" question without making them do mental math
    /// on the date-bucket aggregate.
    private func batchHeader(_ batch: Batch) -> some View {
        let preferred = LocalCurrency.current
        let totalUSD = batch.items.reduce(0.0) { acc, item in
            acc + lineValueUSD(item)
        }
        let totalCopies = batch.items.reduce(0) { $0 + $1.quantity }
        let amountText: String
        if let converted = currencyService.convert(totalUSD, to: preferred) {
            amountText = LocalCurrency.format(converted, currency: preferred)
        } else {
            amountText = LocalCurrency.format(totalUSD, currency: "USD")
        }
        return HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MD3Theme.primary)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(totalCopies) card\(totalCopies == 1 ? "" : "s") · \(relativeDate(batch.timestamp))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .textCase(.uppercase)
            }
            Spacer()
            Text(amountText)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(MD3Theme.primary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .listRowBackground(MD3Theme.primaryContainer.opacity(0.18))
    }

    /// Foil-aware per-item line value, factored out so the batch
    /// header and per-row renderer agree.
    private func lineValueUSD(_ item: CollectionItem) -> Double {
        let nonFoilCount = max(0, item.quantity - item.foilQuantity)
        let nonFoilUnit = item.currentValueUSD
            ?? item.priceAtAddUSD
            ?? item.currentValueFoilUSD
            ?? 0
        let foilUnit = item.currentValueFoilUSD
            ?? item.priceAtAddUSD
            ?? item.currentValueUSD
            ?? 0
        return nonFoilUnit * Double(nonFoilCount) + foilUnit * Double(item.foilQuantity)
    }

    // MARK: - Summary

    /// Headline tile — count of additions in the visible window plus the
    /// at-add value (uses the priceAtAddUSD snapshot taken when each item
    /// was first inserted, so the number reflects "what these cards were
    /// worth when I added them," not today's market).
    @ViewBuilder
    private var summaryHeader: some View {
        let preferred = LocalCurrency.current
        let totalUSD = items.reduce(0.0) { acc, item in acc + lineValueUSD(item) }
        let totalCopies = items.reduce(0) { $0 + $1.quantity }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last 30 days")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.75))
                    .textCase(.uppercase)
                if let converted = currencyService.convert(totalUSD, to: preferred) {
                    Text(LocalCurrency.format(converted, currency: preferred))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MD3Theme.onPrimaryContainer)
                } else {
                    Text(LocalCurrency.format(totalUSD, currency: "USD"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MD3Theme.onPrimaryContainer)
                }
            }
            HStack(spacing: 12) {
                statTile(value: "\(totalCopies)", label: "Copies")
                Divider().frame(height: 28)
                statTile(value: "\(items.count)", label: "Entries")
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [MD3Theme.primaryContainer, MD3Theme.primaryContainer.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(MD3Theme.onPrimaryContainer)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(MD3Theme.onPrimaryContainer.opacity(0.7))
        }
    }

    // MARK: - Row

    private func row(_ item: CollectionItem) -> some View {
        let preferred = LocalCurrency.current
        let lineUSD = lineValueUSD(item)
        let line: Double? = lineUSD > 0 ? lineUSD : nil
        let convertedLine = line.flatMap { currencyService.convert($0, to: preferred) }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.cardName)
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                        .lineLimit(1)
                    if item.quantity > 1 {
                        Text("×\(item.quantity)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MD3Theme.onSurfaceVariant)
                    }
                }
                HStack(spacing: 6) {
                    Text("\(item.setName) · #\(item.collectorNumber)")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .lineLimit(1)
                    Text(relativeDate(item.addedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.8))
                }
            }
            Spacer(minLength: 8)
            if let convertedLine {
                Text(LocalCurrency.format(convertedLine, currency: preferred))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(MD3Theme.onSurface)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary)
            Text("Nothing recent")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Cards added in the last 30 days will appear here. Add some via Batch Scan or the + button on Collection.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Card detail

    @ViewBuilder
    private func cardDetailDestination(for item: CollectionItem) -> some View {
        if let card = resolvedCards[item.scryfallID] {
            CardDetailView(
                card: card,
                repository: cardRepository,
                deckRepository: deckRepository,
                onScanAnother: {}
            )
        } else {
            ProgressView("Loading card…")
                .task { await resolveCard(item) }
        }
    }

    private func resolveCard(_ item: CollectionItem) async {
        guard resolvedCards[item.scryfallID] == nil else { return }
        if let card = try? await cardRepository.fetchCard(
            set: item.setCode,
            collectorNumber: item.collectorNumber
        ) {
            resolvedCards[item.scryfallID] = card
        }
    }

    // MARK: - Data

    /// Pulls the user's collection, keeps the last 30 days, and sorts
    /// newest-first. 30d is a deliberate cap — anything older than that
    /// belongs in the main Collection screen, not "Recently Added."
    private func reload() {
        let all = (try? deckRepository.fetchCollection()) ?? []
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        items = all
            .filter { $0.addedAt >= cutoff }
            .sorted { $0.addedAt > $1.addedAt }
    }

    /// Buckets `items` into the relative-date sections shown by the list.
    /// Returns only non-empty buckets to keep the UI tidy.
    private var sections: [Section] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday

        // Start of week using user's calendar (handles locale-specific week start).
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday

        var buckets: [Bucket: [CollectionItem]] = [:]
        for item in items {
            let bucket: Bucket
            if item.addedAt >= startOfToday {
                bucket = .today
            } else if item.addedAt >= startOfYesterday {
                bucket = .yesterday
            } else if item.addedAt >= weekStart {
                bucket = .lastWeek
            } else if item.addedAt >= monthStart {
                bucket = .lastMonth
            } else {
                bucket = .earlier
            }
            buckets[bucket, default: []].append(item)
        }
        return Bucket.allCases.compactMap { bucket in
            guard let entries = buckets[bucket], !entries.isEmpty else { return nil }
            return Section(bucket: bucket, batches: clusterIntoBatches(entries))
        }
    }

    /// Items added within `batchWindowSeconds` of each other are
    /// treated as a single batch. Input is assumed sorted newest-first.
    private func clusterIntoBatches(_ items: [CollectionItem]) -> [Batch] {
        var clusters: [[CollectionItem]] = []
        var current: [CollectionItem] = []
        var lastTime: Date?
        for item in items {
            if let last = lastTime,
               abs(item.addedAt.timeIntervalSince(last)) > Self.batchWindowSeconds {
                if !current.isEmpty { clusters.append(current) }
                current = []
            }
            current.append(item)
            lastTime = item.addedAt
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters.compactMap { cluster in
            guard let first = cluster.first else { return nil }
            return Batch(timestamp: first.addedAt, items: cluster)
        }
    }
}
