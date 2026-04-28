import SwiftUI

/// Shared "−/qty/+" stepper for scanned-card lists. Used by Batch Scan, Split
/// Cards, and Live Scan so all three scan flows offer identical quantity
/// editing — keeps muscle memory consistent across entry points.
struct ScannedCardQuantityStepper: View {
    let quantity: Int
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    var iconSize: CGFloat = 18
    var range: ClosedRange<Int> = 1...20

    var body: some View {
        let textSize: CGFloat = iconSize >= 20 ? 14 : 13
        let minWidth: CGFloat = iconSize >= 20 ? 28 : 24

        HStack(spacing: 4) {
            Button(action: onDecrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(quantity > range.lowerBound ? MD3Theme.primary : Color.gray.opacity(0.4))
            }
            .disabled(quantity <= range.lowerBound)

            Text("\(quantity)x")
                .font(.system(size: textSize, weight: .bold, design: .rounded))
                .foregroundStyle(MD3Theme.onSurface)
                .monospacedDigit()
                .frame(minWidth: minWidth)

            Button(action: onIncrement) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(quantity < range.upperBound ? MD3Theme.primary : Color.gray.opacity(0.4))
            }
            .disabled(quantity >= range.upperBound)
        }
    }
}
