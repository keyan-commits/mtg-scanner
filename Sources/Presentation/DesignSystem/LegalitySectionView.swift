import SwiftUI

/// Shared format legality display. Used in CardDetailView and CardCopiesDetailView.
struct LegalitySectionView: View {
    let legalities: FormatLegality
    /// If true, wraps content in an MD3Card. If false, uses surface background styling.
    let useCard: Bool

    private let formats: [(String, String)] = [
        ("Standard", "standard"),
        ("Pioneer", "pioneer"),
        ("Modern", "modern"),
        ("Legacy", "legacy"),
        ("Vintage", "vintage"),
        ("Pauper", "pauper"),
        ("Commander", "commander"),
        ("Premodern", "premodern"),
    ]

    init(legalities: FormatLegality, useCard: Bool = true) {
        self.legalities = legalities
        self.useCard = useCard
    }

    var body: some View {
        if useCard {
            MD3Card {
                content
                    .padding(16)
            }
        } else {
            content
                .padding(14)
                .background(MD3Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(MD3Theme.outlineVariant, lineWidth: 1)
                )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Format Legality")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurface)
                HelpButton("Whether this card is allowed in each tournament format. Restricted = limited to 1 copy in the deck.")
            }
            ForEach(formats, id: \.1) { name, key in
                let status = legalities.status(for: key) ?? .notLegal
                HStack {
                    Circle()
                        .fill(LegalityFormatter.color(status))
                        .frame(width: 8, height: 8)
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(MD3Theme.onSurface)
                    Spacer()
                    Text(LegalityFormatter.label(status))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LegalityFormatter.color(status))
                }
            }
        }
    }
}
