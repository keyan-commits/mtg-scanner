import SwiftUI

// MARK: - MD3 Tonal Elevation

/// Material Design 3 elevation using tonal surface color overlays.
///
/// MD3 replaces traditional shadow-based elevation with tonal elevation,
/// where higher elevation surfaces receive a stronger tint of the primary color
/// blended into the surface. Levels 0 through 5 correspond to the MD3 spec.
struct MD3Elevation: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme

    /// Elevation level from 0 (no elevation) to 5 (highest).
    let level: Int

    func body(content: Content) -> some View {
        content
            .background(tintOverlay)
    }

    /// The tonal surface tint overlay opacity mapped to each elevation level.
    ///
    /// MD3 elevation opacities:
    /// - Level 0: 0% (no tint)
    /// - Level 1: 5%
    /// - Level 2: 8%
    /// - Level 3: 11%
    /// - Level 4: 12%
    /// - Level 5: 14%
    private var tintOverlay: some View {
        MD3Theme.surfaceTint
            .opacity(tintOpacity)
    }

    private var tintOpacity: Double {
        switch level {
        case 0: 0.0
        case 1: 0.05
        case 2: 0.08
        case 3: 0.11
        case 4: 0.12
        case 5: 0.14
        default: min(0.14, Double(level) * 0.03)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Applies MD3 tonal elevation at the given level (0-5).
    ///
    /// Higher levels blend more of the primary (surface tint) color
    /// into the surface background, following Material Design 3 guidelines.
    ///
    /// - Parameter level: Elevation level from 0 to 5.
    /// - Returns: A view with the tonal elevation applied.
    func md3Elevation(_ level: Int) -> some View {
        modifier(MD3Elevation(level: level))
    }
}
