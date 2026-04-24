import SwiftUI

/// A minimal sparkline chart for price history. Renders a smooth line
/// showing price trends over time, with the current price highlighted.
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

    var body: some View {
        if filteredPoints.count < 2 {
            Text("Not enough data")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: 80)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                // Price range labels
                HStack {
                    if let first = filteredPoints.first, let last = filteredPoints.last {
                        let change = last.price - first.price
                        let pct = first.price > 0 ? (change / first.price) * 100 : 0
                        Text(String(format: "%@%.0f%%", pct >= 0 ? "+" : "", pct))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(isPositive ? .green : .red)
                    }
                    Spacer()
                    Text(String(format: "$%.2f – $%.2f", minPrice, maxPrice))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Chart
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let height = geometry.size.height

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
                    .stroke(
                        isPositive ? Color.green : Color.red,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )

                    // Fill gradient under the line
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
                    .fill(
                        LinearGradient(
                            colors: [
                                (isPositive ? Color.green : Color.red).opacity(0.2),
                                (isPositive ? Color.green : Color.red).opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(height: 80)
            }
        }
    }
}
