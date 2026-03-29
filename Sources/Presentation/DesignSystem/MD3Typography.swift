import SwiftUI

// MARK: - MD3 Type Scale

/// Material Design 3 type scale using system fonts with sizes and weights per the MD3 specification.
struct MD3Typography {

    // MARK: - Display

    /// Display Large - 57pt, Regular (400)
    static let displayLarge: Font = .system(size: 57, weight: .regular)

    /// Display Medium - 45pt, Regular (400)
    static let displayMedium: Font = .system(size: 45, weight: .regular)

    /// Display Small - 36pt, Regular (400)
    static let displaySmall: Font = .system(size: 36, weight: .regular)

    // MARK: - Headline

    /// Headline Large - 32pt, Regular (400)
    static let headlineLarge: Font = .system(size: 32, weight: .regular)

    /// Headline Medium - 28pt, Regular (400)
    static let headlineMedium: Font = .system(size: 28, weight: .regular)

    /// Headline Small - 24pt, Regular (400)
    static let headlineSmall: Font = .system(size: 24, weight: .regular)

    // MARK: - Title

    /// Title Large - 22pt, Regular (400)
    static let titleLarge: Font = .system(size: 22, weight: .regular)

    /// Title Medium - 16pt, Medium (500)
    static let titleMedium: Font = .system(size: 16, weight: .medium)

    /// Title Small - 14pt, Medium (500)
    static let titleSmall: Font = .system(size: 14, weight: .medium)

    // MARK: - Body

    /// Body Large - 16pt, Regular (400)
    static let bodyLarge: Font = .system(size: 16, weight: .regular)

    /// Body Medium - 14pt, Regular (400)
    static let bodyMedium: Font = .system(size: 14, weight: .regular)

    /// Body Small - 12pt, Regular (400)
    static let bodySmall: Font = .system(size: 12, weight: .regular)

    // MARK: - Label

    /// Label Large - 14pt, Medium (500)
    static let labelLarge: Font = .system(size: 14, weight: .medium)

    /// Label Medium - 12pt, Medium (500)
    static let labelMedium: Font = .system(size: 12, weight: .medium)

    /// Label Small - 11pt, Medium (500)
    static let labelSmall: Font = .system(size: 11, weight: .medium)
}
