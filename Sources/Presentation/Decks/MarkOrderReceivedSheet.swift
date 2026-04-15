import SwiftUI

/// Sheet for bulk-marking deck items as ordered from a single store.
/// Paste the seller's confirmation, the parser extracts qty/name/[set]/price,
/// then preview the matches before applying.
///
/// Supported line formats (one per line):
///   `2 Swords to Plowshares [4ED] = 450ea`
///   `4 Armageddon [4ED] = 720`
///   `1 Strip Mine <1> [4ED] = 990ea`
///   `4 Lightning Bolt = 0.50`
struct MarkOrderReceivedSheet: View {

    /// When nil, the sheet matches against every deck's needed items.
    /// When set, matching is restricted to this deck only.
    let deck: DeckList?
    let deckRepository: DeckListRepository
    let onDone: () -> Void

    // Header fields
    @State private var store: String = ""
    @State private var currency: String = "USD"
    @State private var orderedAt: Date = Date()
    @State private var hasETA: Bool = false
    @State private var eta: Date = Date().addingTimeInterval(60 * 60 * 24 * 14)
    @State private var purchaseURL: String = ""
    @State private var totalDueText: String = ""
    @State private var notes: String = ""
    @State private var recentStores: [String] = []

    // Paste
    @State private var pastedText: String = ""

    // Preview
    @State private var preview: [PreviewLine] = []
    @State private var didParse: Bool = false
    @State private var deckItems: [PurchaseItem] = []
    @State private var editingLine: PreviewLine?
    @State private var editingText: String = ""

    @Environment(\.dismiss) private var dismiss

    /// One row in the parsed preview. Holds either matched deck items or a warning.
    struct PreviewLine: Identifiable {
        let id = UUID()
        let raw: String
        let parsed: OrderPasteParser.ParsedLine?
        var matchedItems: [PurchaseItem] = []
        var status: MatchStatus
        var include: Bool = true
    }

    enum MatchStatus {
        case matched              // Found N needed copies of the right printing
        case wrongPrinting        // Card is in deck but a different set — could still apply
        case partial(Int)         // Found fewer needed copies than requested
        case notInDeck            // Card name doesn't appear in any deck at all
        case alreadyOrdered       // Card exists in deck(s) but no needed copies remain
        case unparseable
    }

    private let currencies = ["USD", "PHP", "JPY", "EUR", "GBP", "CAD", "AUD"]

    var body: some View {
        NavigationStack {
            Group {
                if didParse {
                    previewView
                } else {
                    editorView
                }
            }
            .navigationTitle(deck == nil ? "New Order" : "Bulk Mark Ordered")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(didParse ? "Back" : "Cancel") {
                        if didParse { didParse = false } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        ScreenHelpButton(title: "Bulk Mark Ordered", sections: [
                            HelpSection(icon: "doc.on.clipboard", title: "Paste a seller confirmation",
                                        body: "Drop the seller's order list into the paste area as-is. The parser handles `qty Name [SET] = priceea` lines and skips headers like Total, ETA, and color section markers."),
                            HelpSection(icon: "checkmark.circle.fill", title: "Match statuses",
                                        body: "Green check = exact match. Orange triangle = wrong printing (will apply to first N needed copies). Gray ? = card not in any deck. Gray box = all copies already ordered. Red X = couldn't parse."),
                            HelpSection(icon: "pencil", title: "Edit a parsed line",
                                        body: "Tap the pencil on any preview row (or swipe left) to fix a misparsed line. Save re-parses just that line and updates the preview without losing your other edits."),
                            HelpSection(icon: "switch.2", title: "Apply this line",
                                        body: "Each row has a toggle to skip it on Apply. Useful when the seller can't fulfill some lines or you want to handle them in a separate order."),
                            HelpSection(icon: "dollarsign.circle", title: "Currency",
                                        body: "Pick the currency the seller billed you in (PHP, JPY, USD, etc.). The number is stored as-is — no auto-conversion. Set Total Due if it includes shipping or tax that doesn't match the per-card sum."),
                        ])
                        if didParse {
                            Button("Apply") { apply() }
                                .disabled(!hasAnyApplicable)
                        } else {
                            Button("Parse") { parse() }
                                .disabled(store.trimmingCharacters(in: .whitespaces).isEmpty
                                          || pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
        .onAppear {
            recentStores = (try? deckRepository.recentStores()) ?? []
            if let deck {
                deckItems = (try? deckRepository.fetchItems(deckID: deck.id)) ?? []
            } else {
                deckItems = (try? deckRepository.fetchAllItems()) ?? []
            }
        }
        .sheet(item: $editingLine) { line in
            editLineSheet(line)
        }
    }

    // MARK: - Edit Line Sheet

    @ViewBuilder
    private func editLineSheet(_ line: PreviewLine) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Line text", text: $editingText, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2...4)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                } header: {
                    Text("Edit line")
                } footer: {
                    Text("Format: `<qty> <name> [<SET>] <variant?> = <price>[ea]`. Leave empty to remove this line. The line is re-parsed and re-matched on Save.")
                        .font(.caption2)
                }
            }
            .navigationTitle("Edit Line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { editingLine = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        replaceLine(line, with: editingText)
                        editingLine = nil
                    }
                }
            }
        }
        .onAppear {
            editingText = line.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Editor

    private var editorView: some View {
        Form {
            Section("Store & Order Info") {
                TextField("Store name", text: $store)
                    .autocorrectionDisabled()
                if !recentStores.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(recentStores, id: \.self) { recent in
                                Button(recent) { store = recent }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                HStack {
                    Picker("Currency", selection: $currency) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    HelpButton("Currency for all prices in this order. Not auto-converted — used as-is when displayed later.")
                }
                DatePicker("Ordered", selection: $orderedAt, displayedComponents: .date)
                HStack {
                    Toggle("Has ETA", isOn: $hasETA)
                    HelpButton("Estimated arrival date. Shown on the Orders screen so you know when to expect the package.")
                }
                if hasETA {
                    DatePicker("ETA", selection: $eta, displayedComponents: .date)
                }
                HStack {
                    TextField("Total due (optional)", text: $totalDueText)
                        .keyboardType(.decimalPad)
                    HelpButton("The total billed by the seller (may include shipping/tax). Captured separately from the per-card prices.")
                }
                HStack {
                    TextField("Order URL (optional)", text: $purchaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: purchaseURL) { _, newValue in
                            if store.isEmpty, let detected = PurchaseItem.detectStore(from: newValue) {
                                store = detected
                            }
                        }
                    HelpButton("Order confirmation link. Tap from the order detail later to reopen it in the browser.")
                }
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                TextEditor(text: $pastedText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 220)
            } header: {
                HStack {
                    Text("Paste seller confirmation")
                    HelpButton("Paste the seller's order list as-is. The parser handles `qty Name [SET] = priceea`, skips headers like Total/ETA/<White>, and shows a preview before applying.")
                }
            } footer: {
                Text("Lines like `2 Swords to Plowshares [4ED] = 450ea`. Headers, totals, and color sections are skipped.")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Preview

    private var hasAnyApplicable: Bool {
        preview.contains { $0.include && !$0.matchedItems.isEmpty }
    }

    private var previewView: some View {
        List {
            Section {
                HStack {
                    Text(store).font(.headline)
                    Spacer()
                    Text(currency).font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                let applyCount = preview
                    .filter { $0.include }
                    .reduce(0) { $0 + $1.matchedItems.count }
                Text("\(applyCount) copies will be marked ordered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($preview) { $line in
                    previewRow(line: $line)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                editingLine = line
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                            Button(role: .destructive) {
                                preview.removeAll { $0.id == line.id }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            } footer: {
                Text("Swipe a row to edit or remove. Editing re-parses and re-matches just that line.")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func previewRow(line: Binding<PreviewLine>) -> some View {
        let l = line.wrappedValue
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusIcon(l.status)
                if let parsed = l.parsed {
                    Text("\(parsed.quantity)× \(parsed.name)")
                        .font(.subheadline.weight(.medium))
                } else {
                    Text(l.raw)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let parsed = l.parsed, let price = parsed.pricePerCard {
                    Text("\(currency) \(formatPrice(price))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Button {
                    editingLine = line.wrappedValue
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(MD3Theme.primary)
                }
                .buttonStyle(.plain)
            }
            if let parsed = l.parsed {
                Text(statusDescription(l.status, parsed: parsed, matched: l.matchedItems.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if deck == nil && !l.matchedItems.isEmpty {
                    let deckNames = uniqueDeckNames(l.matchedItems)
                    if !deckNames.isEmpty {
                        Text("Deck: \(deckNames.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !l.matchedItems.isEmpty {
                HStack {
                    Toggle("Apply this line", isOn: line.include)
                        .font(.caption)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    HelpButton("When off, this line is skipped on Apply. Use this to exclude a line you don't want to mark as ordered yet.", size: 11)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusDescription(_ status: MatchStatus, parsed: OrderPasteParser.ParsedLine, matched: Int) -> String {
        switch status {
        case .matched:
            return "Matched \(matched) needed copies"
        case .wrongPrinting:
            return "Found in deck but a different printing — applied to first \(matched) needed copies"
        case .partial(let needed):
            return "Only \(matched) needed copies in deck (asked for \(needed))"
        case .notInDeck:
            return deck == nil
                ? "No deck has this card — add it to a deck first"
                : "Not in this deck — skipped"
        case .alreadyOrdered:
            return "All copies already ordered or arrived — skipped"
        case .unparseable:
            return "Could not parse this line — skipped"
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: MatchStatus) -> some View {
        Group {
            switch status {
            case .matched:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .wrongPrinting:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .partial:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .notInDeck:
                Image(systemName: "questionmark.circle.fill").foregroundStyle(.gray)
            case .alreadyOrdered:
                Image(systemName: "shippingbox.fill").foregroundStyle(.gray)
            case .unparseable:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
        .help(statusIconHelp(status)) // macOS only — harmless on iOS
    }

    private func statusIconHelp(_ status: MatchStatus) -> String {
        switch status {
        case .matched:        return "Exact match in deck"
        case .wrongPrinting:  return "Card is in deck but a different printing — will apply to first N needed copies"
        case .partial:        return "Fewer needed copies than requested"
        case .notInDeck:      return "Card not found in any deck"
        case .alreadyOrdered: return "All copies already ordered or arrived"
        case .unparseable:    return "Could not parse this line — will be skipped"
        }
    }

    // MARK: - Parse

    private func parse() {
        let normalized = pastedText
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
        var result: [PreviewLine] = []
        var claimed: Set<UUID> = []

        for raw in normalized.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if OrderPasteParser.shouldSkip(trimmed) { continue }

            guard let parsed = OrderPasteParser.parseLine(trimmed) else {
                if trimmed.first?.isNumber == true {
                    result.append(PreviewLine(raw: raw, parsed: nil, status: .unparseable))
                }
                continue
            }

            let (matched, status) = matchParsed(parsed, claimed: claimed)
            for item in matched { claimed.insert(item.id) }
            result.append(PreviewLine(raw: raw, parsed: parsed, matchedItems: matched, status: status))
        }

        preview = result
        didParse = true
    }

    /// Re-parses and re-matches a single preview line. Used by the per-row
    /// edit flow. The new line's items are matched against the deck pool
    /// excluding everything still claimed by *other* lines.
    private func replaceLine(_ original: PreviewLine, with newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty / skip → remove the line entirely
        if trimmed.isEmpty || OrderPasteParser.shouldSkip(trimmed) {
            preview.removeAll { $0.id == original.id }
            return
        }

        // Build the set of items claimed by every OTHER preview line
        var otherClaimed: Set<UUID> = []
        for line in preview where line.id != original.id {
            for item in line.matchedItems {
                otherClaimed.insert(item.id)
            }
        }

        guard let parsed = OrderPasteParser.parseLine(trimmed) else {
            // Unparseable — keep the row but flag it
            replaceInPreview(original.id, with: PreviewLine(raw: newText, parsed: nil, status: .unparseable))
            return
        }

        let (matched, status) = matchParsed(parsed, claimed: otherClaimed)
        replaceInPreview(
            original.id,
            with: PreviewLine(raw: newText, parsed: parsed, matchedItems: matched, status: status)
        )
    }

    private func replaceInPreview(_ id: UUID, with newLine: PreviewLine) {
        if let idx = preview.firstIndex(where: { $0.id == id }) {
            // Preserve the user's "include" toggle if applicable
            var line = newLine
            line.include = preview[idx].include
            preview[idx] = line
        }
    }

    /// Matches one parsed line against `deckItems`, excluding any items in
    /// the `claimed` set. Returns the matched items and the resulting status.
    /// Used by both `parse()` and `replaceLine(_:with:)`.
    private func matchParsed(
        _ parsed: OrderPasteParser.ParsedLine,
        claimed: Set<UUID>
    ) -> (items: [PurchaseItem], status: MatchStatus) {
        let nameMatches = deckItems.filter {
            $0.cardName.caseInsensitiveCompare(parsed.name) == .orderedSame
        }
        let needed = nameMatches.filter {
            $0.status == .needed && !claimed.contains($0.id)
        }
        if needed.isEmpty {
            let status: MatchStatus = nameMatches.isEmpty ? .notInDeck : .alreadyOrdered
            return ([], status)
        }
        let exactSet: [PurchaseItem]
        if let set = parsed.setCode {
            exactSet = needed.filter { $0.setCode.caseInsensitiveCompare(set) == .orderedSame }
        } else {
            exactSet = needed
        }
        let setPool = exactSet.isEmpty ? needed : exactSet
        let pool = applyVariantHint(parsed.variant, to: setPool)
        let matched = Array(pool.prefix(parsed.quantity))

        let status: MatchStatus
        if exactSet.isEmpty && parsed.setCode != nil {
            status = .wrongPrinting
        } else if matched.count < parsed.quantity {
            status = .partial(parsed.quantity)
        } else {
            status = .matched
        }
        return (matched, status)
    }

    /// Re-orders the pool so that variant-matching items come first.
    /// Mirrors the convention used by `ImportDecklistSheet.matchVariant`:
    /// - Exact collector-number suffix match wins (e.g. hint "b" → "16b").
    /// - Numeric hint becomes an index into the sorted-by-collector pool
    ///   (`<1>` → first item alphabetically, `<2>` → second, etc).
    /// - If neither rule applies, the pool is returned unchanged.
    private func applyVariantHint(_ hint: String?, to pool: [PurchaseItem]) -> [PurchaseItem] {
        guard let hint, !hint.isEmpty, pool.count > 1 else { return pool }
        let lower = hint.lowercased()

        // Exact suffix match (e.g. "a", "b", "1a", "16b")
        if let exactIdx = pool.firstIndex(where: { $0.collectorNumber.lowercased().hasSuffix(lower) }) {
            var reordered = pool
            let picked = reordered.remove(at: exactIdx)
            reordered.insert(picked, at: 0)
            return reordered
        }

        // Numeric hint → index into sorted-by-collector pool
        if let index = Int(lower), index >= 1, index <= pool.count {
            let sorted = pool.sorted { $0.collectorNumber < $1.collectorNumber }
            let picked = sorted[index - 1]
            var reordered = pool
            if let actualIdx = reordered.firstIndex(where: { $0.id == picked.id }) {
                reordered.remove(at: actualIdx)
                reordered.insert(picked, at: 0)
            }
            return reordered
        }

        return pool
    }

    private func uniqueDeckNames(_ items: [PurchaseItem]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for item in items {
            if let name = item.deck?.name, !seen.contains(name) {
                seen.insert(name)
                result.append(name)
            }
        }
        return result
    }

    private func formatPrice(_ price: Double) -> String { MoneyFormat.compact(price) }

    // MARK: - Apply

    private func apply() {
        var allItems: [PurchaseItem] = []
        var allPrices: [Double?] = []
        for line in preview where line.include && !line.matchedItems.isEmpty {
            for item in line.matchedItems {
                allItems.append(item)
                allPrices.append(line.parsed?.pricePerCard)
            }
        }
        guard !allItems.isEmpty else { return }

        let totalDue = Double(totalDueText.replacingOccurrences(of: ",", with: "."))
        try? deckRepository.createOrder(
            store: store.trimmingCharacters(in: .whitespaces),
            orderedAt: orderedAt,
            eta: hasETA ? eta : nil,
            purchaseURL: purchaseURL.isEmpty ? nil : purchaseURL,
            notes: notes.isEmpty ? nil : notes,
            currency: currency,
            totalDue: totalDue,
            items: allItems,
            prices: allPrices
        )
        onDone()
        dismiss()
    }
}
