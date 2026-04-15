import SwiftUI

/// In-app tutorial for the Orders + Shopping List workflow.
/// Single scrollable screen organized into sections matching
/// `docs/orders-and-shopping-list.md`.
struct HelpScreen: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                lifecycleSection
                Divider()
                section(
                    number: "1",
                    title: "Add cards to a deck",
                    icon: "rectangle.stack.badge.plus",
                    body: "Open My Decks → New Deck. Give it a name and pick a format. Then either tap + to search and add cards one at a time, or tap the import icon to paste a decklist like \"4 Lightning Bolt [M11]\".",
                    extra: "Once cards are imported, they all start as Needed. The deck header shows a cart icon with the count."
                )
                section(
                    number: "2",
                    title: "Open the Shopping List",
                    icon: "cart",
                    body: "From the Scanner home, tap the Shopping List pill. This screen flattens every Needed card across every deck into one list, with prices and which decks need each card.",
                    extra: "Sort by Most Needed (default), Name, or Price ↓ (biggest spend first)."
                )
                shoppingListExampleCard
                section(
                    number: "3",
                    title: "Place an order",
                    icon: "shippingbox.and.arrow.backward",
                    body: "Get a quote from a seller (Hareruya, Card Kingdom, etc.) and place the order. They'll send you a confirmation. Tap the shippingbox button in the top-right of the Shopping List — the bulk-order sheet opens with the paste editor pre-populated.",
                    extra: "You can also open this sheet from inside any deck (the matching is then restricted to that deck)."
                )
                bulkOrderFieldsCard
                parsePreviewLegendCard
                section(
                    number: "4",
                    title: "Track the order",
                    icon: "shippingbox",
                    body: "Tap Orders on the Scanner home. Each row shows the store, ordered date, X/Y arrived, total due, and an ETA badge or Arrived seal. Tap an order to see its items, mark it arrived, edit fields, or delete it.",
                    extra: "Swipe left on a row for quick delete (with confirmation)."
                )
                section(
                    number: "5",
                    title: "Mark as arrived",
                    icon: "checkmark.seal.fill",
                    body: "When the package shows up, open Orders → tap the order → tap \"Mark All Arrived\". Every linked card flips to Arrived in its deck and the order shows the green seal badge.",
                    extra: nil
                )
                Divider()
                parserFormatCard
                Divider()
                scenariosCard
                Divider()
                tipsCard
                Color.clear.frame(height: 24)
            }
            .padding(20)
        }
        .background(MD3Theme.background)
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Lifecycle diagram

    @ViewBuilder
    private var lifecycleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The lifecycle")
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text("Every card copy in a deck moves through three states.")
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)

            HStack(spacing: 8) {
                lifecyclePill(label: "Needed", icon: "cart", color: MD3Theme.onSurfaceVariant)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                lifecyclePill(label: "Ordered", icon: "shippingbox.fill", color: .orange)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                lifecyclePill(label: "Arrived", icon: "checkmark.seal.fill", color: .green)
            }

            VStack(alignment: .leading, spacing: 6) {
                lifecycleRow(icon: "cart", color: MD3Theme.onSurfaceVariant,
                             label: "Needed", desc: "On your wishlist, not yet purchased")
                lifecycleRow(icon: "shippingbox.fill", color: .orange,
                             label: "Ordered", desc: "Purchase placed, package in transit")
                lifecycleRow(icon: "checkmark.seal.fill", color: .green,
                             label: "Arrived", desc: "Card is physically yours")
            }
            .padding(14)
            .background(MD3Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )

            Text("**Shopping List** shows everything still in Needed across all decks. **Orders** shows past purchases (Ordered + Arrived). They're complementary — cards flow from one to the other as you buy them.")
                .font(.footnote)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .padding(.top, 4)
        }
    }

    private func lifecyclePill(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption.weight(.semibold))
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    private func lifecycleRow(icon: String, color: Color, label: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurface)
                .frame(width: 70, alignment: .leading)
            Text(desc)
                .font(.caption)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
            Spacer()
        }
    }

    // MARK: - Numbered Section

    @ViewBuilder
    private func section(number: String, title: String, icon: String, body: String, extra: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(MD3Theme.primaryContainer)
                        .frame(width: 28, height: 28)
                    Text(number)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MD3Theme.onPrimaryContainer)
                }
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(MD3Theme.primary)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurface)
            }
            Text(body)
                .font(.callout)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
            if let extra {
                Text(extra)
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 38)
            }
        }
    }

    // MARK: - Shopping List example card

    @ViewBuilder
    private var shoppingListExampleCard: some View {
        infoCard(title: "What a Shopping List row looks like") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("4×")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .frame(minWidth: 28, alignment: .trailing)
                    Text("Lightning Bolt")
                        .font(MD3Typography.bodyMedium)
                        .foregroundStyle(MD3Theme.onSurface)
                    Text("{R}")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    Text("$2.00")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MD3Theme.primary)
                }
                HStack {
                    Text("Magic 2011 · #146")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                    Spacer()
                    Text("$0.50 ea")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
                HStack(spacing: 6) {
                    chip("Modern Burn ×4")
                }
                .padding(.top, 2)
            }
            .padding(10)
            .background(MD3Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("**Quantity** × name + mana cost + line total. Below: set, per-card price, and chips showing which decks need this card.")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(MD3Theme.onSecondaryContainer)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(MD3Theme.secondaryContainer)
            .clipShape(Capsule())
    }

    // MARK: - Bulk Order fields card

    @ViewBuilder
    private var bulkOrderFieldsCard: some View {
        infoCard(title: "Filling in the bulk order sheet") {
            VStack(alignment: .leading, spacing: 8) {
                fieldRow("Store name", "Autocomplete from history")
                fieldRow("Currency", "USD, PHP, JPY, EUR, GBP, CAD, AUD. Not auto-converted.")
                fieldRow("Ordered date", "Defaults to today")
                fieldRow("Has ETA + ETA date", "Optional, shown on the Orders screen")
                fieldRow("Total due", "What the seller billed (may include shipping/tax)")
                fieldRow("Order URL", "Confirmation link, reopens later in browser")
                fieldRow("Notes", "Free-form")
                fieldRow("Paste seller confirmation", "Drop the seller's text — parser handles the rest")
            }
        }
    }

    private func fieldRow(_ label: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(MD3Theme.onSurfaceVariant)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurface)
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        }
    }

    // MARK: - Parse preview legend

    @ViewBuilder
    private var parsePreviewLegendCard: some View {
        infoCard(title: "What the preview icons mean") {
            VStack(alignment: .leading, spacing: 10) {
                legendRow("checkmark.circle.fill", .green, "Matched", "Exact match — N copies will be marked ordered")
                legendRow("exclamationmark.triangle.fill", .orange, "Wrong printing", "Card found but in a different set — applied to first N needed copies")
                legendRow("exclamationmark.circle.fill", .orange, "Partial", "Fewer needed copies than the paste asked for")
                legendRow("questionmark.circle.fill", .gray, "Not in any deck", "Add the card to a deck first")
                legendRow("shippingbox.fill", .gray, "Already ordered", "All copies are already ordered or arrived")
                legendRow("xmark.circle.fill", .red, "Unparseable", "Could not read this line — check the format")
            }
            Text("Each row has an \"Apply this line\" toggle so you can selectively skip lines before tapping Apply.")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .padding(.top, 4)
        }
    }

    private func legendRow(_ icon: String, _ color: Color, _ label: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurface)
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        }
    }

    // MARK: - Parser format

    @ViewBuilder
    private var parserFormatCard: some View {
        infoCard(title: "Parser format reference") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Each paste line should look like:")
                    .font(.caption)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Text("<qty> <card name> [<SET>] <variant?> = <price>[ea]")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MD3Theme.onSurface)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MD3Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Group {
                    Text("**Examples**").font(.caption).foregroundStyle(MD3Theme.onSurface)
                    Text("4 Savannah Lions [4ED] = 530ea")
                    Text("1 Order of Leitbur <1> [FEM] = 30ea")
                    Text("4 Lightning Bolt [M11] = 0.50, eBay seller")
                    Text("15 Plains <A> [ICE] = 50ea")
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(MD3Theme.onSurfaceVariant)

                Text("**Auto-skipped:** lines starting with Total, Confirmed, ETA, Details, Shipping, Subtotal, Tax, // — and color section markers like <White>.")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .padding(.top, 4)

                Text("**Variants:** Use <1>, <2>, <3>, <4> to route to specific art variants (matched by collector number index).")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)

                Text("**Trailing notes** after the price (like \", Card Kingdom\") are ignored — feel free to leave them in.")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
        }
    }

    // MARK: - Common scenarios

    @ViewBuilder
    private var scenariosCard: some View {
        infoCard(title: "Common scenarios") {
            VStack(alignment: .leading, spacing: 12) {
                scenario("I made a mistake on an order",
                         "Open the order → tap \"Delete Order (reset items to Needed)\". Items go back to Needed in their decks. Re-paste from the Shopping List.")
                scenario("Seller billed me in PHP but cards are JPY-priced",
                         "Set Currency = PHP and enter prices in PHP. The app stores currency + amount together. Scryfall USD prices in the Shopping List are unrelated estimates.")
                scenario("My paste has notes after the price",
                         "Anything after the price is dropped silently. Lines like \"4 Contagion [ALL] = 150ea, Card Kingdom — confirmed\" parse correctly.")
                scenario("I have multiple variants of the same card",
                         "Use <1>, <2>, <3>, <4> in the paste. The matcher routes each line to the right deck variant by collector-number index.")
                scenario("Got \"Card not in deck\" but the card is there",
                         "The match is by exact name. Check for typos or extra whitespace. \"All copies already ordered\" (gray box icon) means a different thing — the card exists but every copy is already ordered/arrived.")
                scenario("I want to see only one deck's orders",
                         "Open the deck → tap the shippingbox icon in the toolbar. The Orders screen filters to that deck only.")
            }
        }
    }

    private func scenario(_ q: String, _ a: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Q: \(q)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurface)
            Text("A: \(a)")
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Tips card

    @ViewBuilder
    private var tipsCard: some View {
        infoCard(title: "Tips") {
            VStack(alignment: .leading, spacing: 8) {
                tipRow("info.circle", "Look for the ⓘ icons throughout the app. Tap one for a one-line explanation of any term.")
                tipRow("hand.tap", "Long-press a deck row in My Decks to edit it. Same for cards in a deck list.")
                tipRow("rectangle.stack", "Each card detail screen has a \"Change Printing\" button — applies to all copies of that card in the deck at once.")
                tipRow("arrow.left.arrow.right", "Editing an order's store/currency/date cascades to every linked item. So if you typo'd \"Card Kingdom\" as \"Care Kingdom\", you can fix it once.")
            }
        }
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(MD3Theme.primary)
                .frame(width: 18)
            Text(text)
                .font(.caption2)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Generic info card

    @ViewBuilder
    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MD3Theme.onSurface)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MD3Theme.outlineVariant, lineWidth: 1)
        )
    }
}
