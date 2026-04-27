import SwiftUI

/// Shared archetype row showing deck name, format, era, and card quantities.
/// Used in CardDetailView and CardCopiesDetailView classic archetypes sections.
struct ArchetypeRowView: View {
    let archetype: ClassicArchetype
    let mainQty: Int
    let sideQty: Int

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(archetype.name)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                Text("\(archetype.format) \u{00B7} \(archetype.era)")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }
            Spacer()
            HStack(spacing: 4) {
                if mainQty > 0 {
                    Text("\(mainQty)\u{00D7}")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MD3Theme.primary)
                        .monospacedDigit()
                }
                if sideQty > 0 {
                    Text("(SB \(sideQty))")
                        .font(.caption2)
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
