import SwiftUI
import UIKit

// MARK: - MD3 Color Scheme

/// Material Design 3 color roles adapted for a Magic: The Gathering dark/mystic theme.
/// All colors are adaptive, providing both light and dark mode variants.
struct MD3Theme {

    // MARK: - Primary (Deep Arcane Purple)

    static let primary = Color(light: Color(red: 0.42, green: 0.30, blue: 0.72),
                               dark: Color(red: 0.81, green: 0.73, blue: 1.0))
    static let onPrimary = Color(light: .white,
                                 dark: Color(red: 0.18, green: 0.06, blue: 0.46))
    static let primaryContainer = Color(light: Color(red: 0.91, green: 0.85, blue: 1.0),
                                        dark: Color(red: 0.30, green: 0.17, blue: 0.58))
    static let onPrimaryContainer = Color(light: Color(red: 0.12, green: 0.0, blue: 0.36),
                                          dark: Color(red: 0.91, green: 0.85, blue: 1.0))

    // MARK: - Secondary (Muted Amethyst)

    static let secondary = Color(light: Color(red: 0.39, green: 0.35, blue: 0.51),
                                 dark: Color(red: 0.79, green: 0.75, blue: 0.92))
    static let onSecondary = Color(light: .white,
                                   dark: Color(red: 0.18, green: 0.15, blue: 0.29))
    static let secondaryContainer = Color(light: Color(red: 0.90, green: 0.87, blue: 1.0),
                                          dark: Color(red: 0.28, green: 0.25, blue: 0.40))
    static let onSecondaryContainer = Color(light: Color(red: 0.10, green: 0.07, blue: 0.20),
                                            dark: Color(red: 0.90, green: 0.87, blue: 1.0))

    // MARK: - Tertiary (Mystic Gold)

    static let tertiary = Color(light: Color(red: 0.50, green: 0.39, blue: 0.15),
                                dark: Color(red: 0.90, green: 0.80, blue: 0.55))
    static let onTertiary = Color(light: .white,
                                  dark: Color(red: 0.25, green: 0.17, blue: 0.0))
    static let tertiaryContainer = Color(light: Color(red: 1.0, green: 0.92, blue: 0.76),
                                         dark: Color(red: 0.38, green: 0.28, blue: 0.04))
    static let onTertiaryContainer = Color(light: Color(red: 0.16, green: 0.10, blue: 0.0),
                                           dark: Color(red: 1.0, green: 0.92, blue: 0.76))

    // MARK: - Error

    static let error = Color(light: Color(red: 0.73, green: 0.11, blue: 0.11),
                             dark: Color(red: 1.0, green: 0.72, blue: 0.68))
    static let onError = Color(light: .white,
                               dark: Color(red: 0.41, green: 0.0, blue: 0.02))
    static let errorContainer = Color(light: Color(red: 1.0, green: 0.85, blue: 0.82),
                                      dark: Color(red: 0.56, green: 0.04, blue: 0.06))
    static let onErrorContainer = Color(light: Color(red: 0.25, green: 0.0, blue: 0.02),
                                        dark: Color(red: 1.0, green: 0.85, blue: 0.82))

    // MARK: - Background & Surface

    static let background = Color(light: Color(red: 0.99, green: 0.97, blue: 1.0),
                                  dark: Color(red: 0.07, green: 0.06, blue: 0.09))
    static let onBackground = Color(light: Color(red: 0.11, green: 0.10, blue: 0.13),
                                    dark: Color(red: 0.90, green: 0.88, blue: 0.93))
    static let surface = Color(light: Color(red: 0.99, green: 0.97, blue: 1.0),
                               dark: Color(red: 0.07, green: 0.06, blue: 0.09))
    static let onSurface = Color(light: Color(red: 0.11, green: 0.10, blue: 0.13),
                                 dark: Color(red: 0.90, green: 0.88, blue: 0.93))
    static let surfaceVariant = Color(light: Color(red: 0.90, green: 0.87, blue: 0.94),
                                      dark: Color(red: 0.28, green: 0.26, blue: 0.33))
    static let onSurfaceVariant = Color(light: Color(red: 0.28, green: 0.26, blue: 0.33),
                                        dark: Color(red: 0.79, green: 0.77, blue: 0.84))

    // MARK: - Outline

    static let outline = Color(light: Color(red: 0.47, green: 0.44, blue: 0.52),
                               dark: Color(red: 0.60, green: 0.57, blue: 0.65))
    static let outlineVariant = Color(light: Color(red: 0.79, green: 0.77, blue: 0.84),
                                      dark: Color(red: 0.28, green: 0.26, blue: 0.33))

    // MARK: - Surface Tint (used for MD3 tonal elevation)

    static let surfaceTint = primary
}

// MARK: - Color Convenience Initializer for Light/Dark Adaptive Colors

extension Color {
    /// Creates an adaptive color that resolves to different values in light and dark mode.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            switch traits.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }
}
