import SwiftUI
import CoreGraphics

// MARK: - Deck Grid Overlay View

/// Displays a photo with an adjustable grid overlay for deck scanning.
/// Users can adjust rows and columns to match their card layout, then process the grid.
struct DeckGridOverlayView: View {

    let image: CGImage
    @Binding var rows: Int
    @Binding var columns: Int
    let onProcess: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            gridImageView
                .padding(.horizontal, 8)

            gridControls
                .padding(.horizontal, 16)

            MD3FilledButton("Process Grid") {
                onProcess()
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Grid Image

    private var gridImageView: some View {
        GeometryReader { geometry in
            let imageAspect = CGFloat(image.width) / CGFloat(image.height)
            let availableWidth = geometry.size.width
            let availableHeight = geometry.size.height
            let fittedSize = fittedImageSize(
                imageAspect: imageAspect,
                availableWidth: availableWidth,
                availableHeight: availableHeight
            )
            let offsetX = (availableWidth - fittedSize.width) / 2
            let offsetY = (availableHeight - fittedSize.height) / 2

            ZStack {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .position(
                        x: availableWidth / 2,
                        y: availableHeight / 2
                    )

                gridOverlay(size: fittedSize)
                    .position(
                        x: offsetX + fittedSize.width / 2,
                        y: offsetY + fittedSize.height / 2
                    )

                cellNumbers(size: fittedSize)
                    .position(
                        x: offsetX + fittedSize.width / 2,
                        y: offsetY + fittedSize.height / 2
                    )
            }
        }
    }

    // MARK: - Grid Lines

    private func gridOverlay(size: CGSize) -> some View {
        Canvas { context, _ in
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rows)

            // Vertical lines
            for col in 1..<columns {
                let x = CGFloat(col) * cellWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(MD3Theme.primary.opacity(0.7)), lineWidth: 1.5)
            }

            // Horizontal lines
            for row in 1..<rows {
                let y = CGFloat(row) * cellHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(MD3Theme.primary.opacity(0.7)), lineWidth: 1.5)
            }

            // Border
            let borderRect = CGRect(origin: .zero, size: size)
            context.stroke(Path(borderRect), with: .color(MD3Theme.primary.opacity(0.5)), lineWidth: 2)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    // MARK: - Cell Numbers

    private func cellNumbers(size: CGSize) -> some View {
        Canvas { context, _ in
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rows)

            for row in 0..<rows {
                for col in 0..<columns {
                    let number = row * columns + col + 1
                    let x = CGFloat(col) * cellWidth + cellWidth / 2
                    let y = CGFloat(row) * cellHeight + cellHeight / 2
                    let text = Text("\(number)")
                        .font(MD3Typography.labelSmall)
                        .foregroundStyle(.white.opacity(0.8))
                    context.draw(text, at: CGPoint(x: x, y: y))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    // MARK: - Grid Controls

    private var gridControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Rows: \(rows)")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                    .frame(width: 80, alignment: .leading)

                Stepper("", value: $rows, in: 1...5)
                    .labelsHidden()
                    .tint(MD3Theme.primary)
            }

            HStack {
                Text("Columns: \(columns)")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurface)
                    .frame(width: 80, alignment: .leading)

                Stepper("", value: $columns, in: 1...10)
                    .labelsHidden()
                    .tint(MD3Theme.primary)
            }

            Text("\(rows * columns) cells")
                .font(MD3Typography.labelMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
        }
    }

    // MARK: - Helpers

    private func fittedImageSize(
        imageAspect: CGFloat,
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> CGSize {
        let containerAspect = availableWidth / availableHeight
        if imageAspect > containerAspect {
            let width = availableWidth
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = availableHeight
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
}
