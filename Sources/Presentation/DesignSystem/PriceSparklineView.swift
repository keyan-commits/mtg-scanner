import SwiftUI

/// Interactive sparkline chart for price history. Drag across the chart
/// to scrub through data points and see date + price at that position.
struct PriceSparklineView: View {

    let dataPoints: [(date: Date, price: Double)]
    let timeRange: TimeRange

    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "7D"
        case month = "30D"
        case year = "1Y"
        case allTime = "ALL"

        var id: String { rawValue }

        var cutoff: Date {
            switch self {
            case .week: return Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            case .month: return Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            case .year: return Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
            case .allTime: return Date.distantPast
            }
        }
    }

    @State private var scrubIndex: Int?

    private var filteredPoints: [(date: Date, price: Double)] {
        let cutoff = timeRange.cutoff
        return dataPoints.filter { $0.date >= cutoff }
    }

    private var minPrice: Double { filteredPoints.map(\.price).min() ?? 0 }
    private var maxPrice: Double { filteredPoints.map(\.price).max() ?? 1 }
    private var priceRange: Double { max(maxPrice - minPrice, 0.01) }

    private var isPositive: Bool {
        guard let first = filteredPoints.first, let last = filteredPoints.last else { return true }
        return last.price >= first.price
    }

    private var lineColor: Color { isPositive ? .green : .red }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        if filteredPoints.count < 2 {
            Text("Not enough data")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: 80)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                headerRow
                chartArea
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        if let idx = scrubIndex, idx >= 0, idx < filteredPoints.count {
            // Scrubbing: show date + price at finger position
            let point = filteredPoints[idx]
            HStack {
                Text(Self.dateFormatter.string(from: point.date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "$%.2f", point.price))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(lineColor)
            }
        } else {
            // Default: show percentage change + range
            HStack {
                if let first = filteredPoints.first, let last = filteredPoints.last {
                    let change = last.price - first.price
                    let pct = first.price > 0 ? (change / first.price) * 100 : 0
                    Text(String(format: "%@%.0f%%", pct >= 0 ? "+" : "", pct))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(lineColor)
                }
                Spacer()
                Text(String(format: "$%.2f – $%.2f", minPrice, maxPrice))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Chart

    private var chartArea: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let count = filteredPoints.count

            ZStack {
                // Fill gradient
                fillPath(width: width, height: height)
                    .fill(
                        LinearGradient(
                            colors: [lineColor.opacity(0.2), lineColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Line
                linePath(width: width, height: height)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Scrub indicator
                if let idx = scrubIndex, idx >= 0, idx < count {
                    let x = width * CGFloat(idx) / CGFloat(count - 1)
                    let point = filteredPoints[idx]
                    let y = height * (1 - CGFloat((point.price - minPrice) / priceRange))

                    // Vertical line
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                    .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Dot
                    Circle()
                        .fill(lineColor)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = max(0, min(1, value.location.x / width))
                        scrubIndex = Int(round(fraction * CGFloat(count - 1)))
                    }
                    .onEnded { _ in
                        scrubIndex = nil
                    }
            )
        }
        .frame(height: 80)
    }

    // MARK: - Paths

    private func linePath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            for (index, point) in filteredPoints.enumerated() {
                let x = width * CGFloat(index) / CGFloat(filteredPoints.count - 1)
                let y = height * (1 - CGFloat((point.price - minPrice) / priceRange))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func fillPath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            for (index, point) in filteredPoints.enumerated() {
                let x = width * CGFloat(index) / CGFloat(filteredPoints.count - 1)
                let y = height * (1 - CGFloat((point.price - minPrice) / priceRange))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.addLine(to: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.closeSubpath()
        }
    }
}
