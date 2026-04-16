import SwiftUI

/// Sheet for importing a decklist by pasting text. Supports formats like:
///   `4 Savannah Lions [4ED]`
///   `1 Order of Leitbur <1> [FEM]`
///   `15 Plains <A> [ICE]`
///   `4 Lightning Bolt`
struct ImportDecklistSheet: View {

    let deck: DeckList
    let deckRepository: DeckListRepository
    let cardRepository: CardRepositoryProtocol
    let defaultZone: String
    let onDone: () -> Void

    init(deck: DeckList, deckRepository: DeckListRepository, cardRepository: CardRepositoryProtocol, defaultZone: String = "mainboard", onDone: @escaping () -> Void) {
        self.deck = deck
        self.deckRepository = deckRepository
        self.cardRepository = cardRepository
        self.defaultZone = defaultZone
        self.onDone = onDone
    }

    /// A wrong-set line that the user can resolve by picking a printing.
    struct WrongSetEntry: Identifiable {
        let id = UUID()
        let raw: String
        let quantity: Int
        let cardName: String
    }

    @State private var pastedText: String = ""
    @State private var isImporting: Bool = false
    @State private var resultMessage: String?
    @State private var notFoundLines: [String] = []
    @State private var wrongSetEntries: [WrongSetEntry] = []
    @State private var resolvingEntry: WrongSetEntry?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let resultMessage {
                    resultView(message: resultMessage)
                } else {
                    editorView
                }
            }
            .navigationTitle("Import to \(deck.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if resultMessage != nil {
                        Button("Done") {
                            onDone()
                            dismiss()
                        }
                    } else {
                        Button("Import") {
                            Task { await runImport() }
                        }
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                    }
                }
            }
        }
    }

    // MARK: - Editor

    private var editorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste your decklist")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Text("Format: 4 Lightning Bolt [M11], or 4 Lightning Bolt")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            TextEditor(text: $pastedText)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 16)

            if isImporting {
                HStack {
                    ProgressView()
                    Text("Importing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }

            Spacer()
        }
        .padding(.bottom, 16)
    }

    // MARK: - Result

    private func resultView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
                Text(message)
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !wrongSetEntries.isEmpty {
                        wrongSetSection
                    }
                    if !notFoundLines.isEmpty {
                        warningSection(
                            title: "Not found (\(notFoundLines.count))",
                            subtitle: "Card name not in the database. Check spelling.",
                            color: .red,
                            lines: notFoundLines
                        )
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()
        }
        .sheet(item: $resolvingEntry) { entry in
            PickPrintingSheet(
                cardName: entry.cardName,
                quantity: entry.quantity,
                cardRepository: cardRepository
            ) { card in
                _ = try? deckRepository.addItem(card: card, quantity: entry.quantity, to: deck)
                wrongSetEntries.removeAll { $0.id == entry.id }
                resolvingEntry = nil
                refreshResultMessage()
            }
        }
    }

    private var wrongSetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("Wrong set (\(wrongSetEntries.count))")
                    .font(.subheadline.bold())
            }
            Text("Tap a line to pick the correct printing.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(wrongSetEntries) { entry in
                    Button {
                        resolvingEntry = entry
                    } label: {
                        HStack {
                            Text(entry.raw)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    if entry.id != wrongSetEntries.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func warningSection(title: String, subtitle: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.bold())
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Recomputes the success message based on current counters.
    private func refreshResultMessage() {
        // Just update the count of wrong-set / not found
        var parts: [String] = []
        if !wrongSetEntries.isEmpty { parts.append("\(wrongSetEntries.count) wrong set") }
        if !notFoundLines.isEmpty { parts.append("\(notFoundLines.count) not found") }
        if parts.isEmpty {
            resultMessage = "All resolved!"
        } else {
            resultMessage = "Pending: " + parts.joined(separator: ", ")
        }
    }

    // MARK: - Import Logic

    private func runImport() async {
        isImporting = true
        defer { isImporting = false }

        // Normalize smart quotes globally before parsing
        let normalized = pastedText
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
        let lines = normalized.components(separatedBy: .newlines)
        var added = 0
        var notFound: [String] = []
        var wrongSet: [WrongSetEntry] = []
        var currentZone = defaultZone

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("//") { continue }
            let lower = trimmed.lowercased()
            // Detect zone headers (flexible matching)
            let sideboardHeaders = ["sideboard", "sideboard:", "sb:", "sb", "side", "side:"]
            let mainboardHeaders = ["mainboard", "mainboard:", "mb:", "mb", "main", "main:", "maindeck", "maindeck:"]
            if sideboardHeaders.contains(lower) {
                currentZone = "sideboard"
                continue
            }
            if mainboardHeaders.contains(lower) {
                currentZone = "mainboard"
                continue
            }

            guard let parsed = parseLine(trimmed) else {
                notFound.append(raw)
                continue
            }

            let result = await resolveCard(name: parsed.name, setCode: parsed.setCode, variant: parsed.variant)
            switch result {
            case .matched(let card):
                _ = try? deckRepository.addItem(card: card, quantity: parsed.quantity, to: deck, zone: currentZone)
                added += parsed.quantity
            case .wrongSet:
                wrongSet.append(WrongSetEntry(raw: raw, quantity: parsed.quantity, cardName: parsed.name))
            case .notFound:
                notFound.append(raw)
            }
        }

        notFoundLines = notFound
        wrongSetEntries = wrongSet

        var parts: [String] = ["Added \(added) cards"]
        if !wrongSet.isEmpty { parts.append("\(wrongSet.count) wrong set") }
        if !notFound.isEmpty { parts.append("\(notFound.count) not found") }
        resultMessage = parts.joined(separator: ", ")
    }

    // MARK: - Parser

    /// Delegates to the canonical `OrderPasteParser`. Decklist imports
    /// don't carry prices, so the `pricePerCard` field is ignored.
    private func parseLine(_ line: String) -> OrderPasteParser.ParsedLine? {
        OrderPasteParser.parseLine(line)
    }

    // MARK: - Card Resolution

    private enum ResolveResult {
        case matched(Card)
        case wrongSet // card name exists but not in the requested set
        case notFound
    }

    private func resolveCard(name: String, setCode: String?, variant: String?) async -> ResolveResult {
        // 1. If a set code was specified, try to find the card in that exact set
        if let setCode {
            let variants = (try? await cardRepository.findVariants(name: name, setCode: setCode)) ?? []
            if !variants.isEmpty {
                if let variant, let match = matchVariant(variants, hint: variant) {
                    return .matched(match)
                }
                return .matched(variants.first!)
            }

            // Card name might exist in DB but not in the requested set → flag it
            let allPrintings = (try? await cardRepository.findAllPrintings(name: name)) ?? []
            if !allPrintings.isEmpty {
                return .wrongSet
            }
            return .notFound
        }

        // 2. No set code — pick any printing of the card name
        let printings = (try? await cardRepository.findAllPrintings(name: name)) ?? []
        if let first = printings.first {
            return .matched(first)
        }

        // 3. Last resort: fuzzy lookup
        if let card = try? await cardRepository.identifyCard(name: name) {
            return .matched(card)
        }
        return .notFound
    }

    /// Picks the variant matching a hint. The hint may be `1`, `2`, `A`, `B` etc.
    /// Maps to the printing whose collector number ends with that character.
    private func matchVariant(_ variants: [Card], hint: String) -> Card? {
        let lowerHint = hint.lowercased()

        // Exact suffix match: collector number ends with the hint (e.g., "16a", "16b")
        if let exact = variants.first(where: { $0.collectorNumber.lowercased().hasSuffix(lowerHint) }) {
            return exact
        }

        // Numeric hint → match by sorted index (e.g., <1> → first variant alphabetically)
        if let index = Int(lowerHint), index >= 1, index <= variants.count {
            let sorted = variants.sorted { $0.collectorNumber < $1.collectorNumber }
            return sorted[index - 1]
        }

        return nil
    }
}
