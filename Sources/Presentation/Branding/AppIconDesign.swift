import SwiftUI

/// SwiftUI rendering of the MTG Keyan app icon. Designed to mirror the
/// existing Keyan brand badge (vintage circular crest, cream interior,
/// red border ring, curved text on top + bottom arcs, cursive "Keyan"
/// centerpiece) but reskinned for the MTG app:
///   - Top arc:    "MAGIC THE GATHERING"
///   - Bottom arc: "TRACKER"
///   - Side accents: mana pips in the 5 MTG colors instead of stars
///
/// The view renders at any size; pass `1024` as the side length when
/// exporting to a PNG for the App Store / asset catalog. iOS will mask
/// the rounded square automatically — no need to pre-clip the corners.
struct AppIconDesign: View {

    /// Side length in points. The whole design scales to fill this.
    var size: CGFloat = 1024

    // MARK: - Brand palette (matched against the laundry badge)
    private let cream = Color(red: 0.952, green: 0.910, blue: 0.812)
    private let red = Color(red: 0.785, green: 0.211, blue: 0.179)
    private let darkRed = Color(red: 0.580, green: 0.140, blue: 0.110)
    private let navy = Color(red: 0.176, green: 0.262, blue: 0.502)
    private let gold = Color(red: 0.910, green: 0.722, blue: 0.278)

    // MARK: - 5 MTG mana colors
    private let manaW = Color(red: 0.973, green: 0.965, blue: 0.847)
    private let manaU = Color(red: 0.701, green: 0.808, blue: 0.918)
    private let manaB = Color(red: 0.145, green: 0.145, blue: 0.145)
    private let manaR = Color(red: 0.922, green: 0.624, blue: 0.510)
    private let manaG = Color(red: 0.639, green: 0.753, blue: 0.584)

    var body: some View {
        ZStack {
            // 1. Background — solid cream so iOS gets a non-transparent icon
            Rectangle().fill(cream)

            // 2. Outer thick red ring + thin gold inner border
            Circle()
                .strokeBorder(red, lineWidth: size * 0.082)
                .padding(size * 0.020)
            Circle()
                .strokeBorder(gold, lineWidth: size * 0.006)
                .padding(size * 0.108)

            // 3. Top + bottom curved labels
            curvedText("MAGIC THE GATHERING", radius: size * 0.398, top: true)
            curvedText("TRACKER", radius: size * 0.398, top: false)

            // 4. Side mana pips (W/U on left, R/G on right, B at the bottom)
            sideManaPips

            // 5. Hero "Keyan" cursive centerpiece with red drop shadow
            keyanCenter

            // 6. Subtle inner texture / aging — tiny dotted ring
            Circle()
                .strokeBorder(darkRed.opacity(0.18), style: StrokeStyle(lineWidth: size * 0.003, dash: [size * 0.008, size * 0.012]))
                .padding(size * 0.146)
        }
        .frame(width: size, height: size)
        .clipped()
    }

    // MARK: - Cursive centerpiece

    private var keyanCenter: some View {
        let fontSize = size * 0.42
        return ZStack {
            // Drop shadow (red, offset down-right)
            Text("Keyan")
                .font(.custom("Snell Roundhand", size: fontSize).weight(.black))
                .foregroundStyle(red)
                .offset(x: size * 0.012, y: size * 0.012)
            // Main text (navy)
            Text("Keyan")
                .font(.custom("Snell Roundhand", size: fontSize).weight(.black))
                .foregroundStyle(navy)
        }
    }

    // MARK: - Side mana pips

    private var sideManaPips: some View {
        // 5 pips arranged as a small horizontal row above the bottom arc,
        // mirroring how the original logo has decoration around the
        // cursive name. Sits between Keyan and the "TRACKER" label.
        let pipSize = size * 0.044
        let yOffset = size * 0.252
        return HStack(spacing: pipSize * 0.55) {
            manaPip(color: manaW, diameter: pipSize)
            manaPip(color: manaU, diameter: pipSize)
            manaPip(color: manaB, diameter: pipSize)
            manaPip(color: manaR, diameter: pipSize)
            manaPip(color: manaG, diameter: pipSize)
        }
        .offset(y: yOffset)
    }

    private func manaPip(color: Color, diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(color)
            Circle()
                .strokeBorder(darkRed, lineWidth: diameter * 0.08)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.18), radius: diameter * 0.05, x: 0, y: diameter * 0.04)
    }

    // MARK: - Curved text

    /// Renders a string along the top or bottom arc of a circle. Letters
    /// are placed individually, each rotated tangent to the arc so the
    /// text reads naturally from outside the badge.
    @ViewBuilder
    private func curvedText(_ text: String, radius: CGFloat, top: Bool) -> some View {
        let chars = Array(text)
        let totalArcDegrees: Double = top ? 130 : 90
        let perChar: Double = chars.count > 1 ? totalArcDegrees / Double(chars.count - 1) : 0
        let startAngle: Double = top
            ? -90 - totalArcDegrees / 2
            : 90 - totalArcDegrees / 2
        let fontSize = size * (top ? 0.062 : 0.058)
        ZStack {
            ForEach(Array(chars.enumerated()), id: \.offset) { idx, char in
                let angleDeg = startAngle + Double(idx) * perChar
                let angleRad = angleDeg * .pi / 180
                let x = radius * cos(angleRad)
                let y = radius * sin(angleRad)
                // Bottom-arc text needs to read left-to-right too: rotate
                // by 180° so each glyph faces outward.
                let rotation = top ? angleDeg + 90 : angleDeg - 90
                Text(String(char))
                    .font(.system(size: fontSize, weight: .heavy, design: .serif))
                    .foregroundStyle(red)
                    .rotationEffect(.degrees(rotation))
                    .offset(x: x, y: y)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AppIconDesign(size: 360)
        .background(Color.gray)
}
