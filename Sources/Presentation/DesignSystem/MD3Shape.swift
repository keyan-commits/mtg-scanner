import SwiftUI

// MARK: - MD3 Shape Scale

/// Material Design 3 shape scale providing consistent corner radius values.
struct MD3Shape {

    /// Extra small corner radius (4pt). Use for small components like chips.
    static let extraSmall = RoundedRectangle(cornerRadius: 4, style: .continuous)

    /// Small corner radius (8pt). Use for buttons and small cards.
    static let small = RoundedRectangle(cornerRadius: 8, style: .continuous)

    /// Medium corner radius (12pt). Use for cards and dialogs.
    static let medium = RoundedRectangle(cornerRadius: 12, style: .continuous)

    /// Large corner radius (16pt). Use for large cards and sheets.
    static let large = RoundedRectangle(cornerRadius: 16, style: .continuous)

    /// Extra large corner radius (28pt). Use for prominent surfaces and FABs.
    static let extraLarge = RoundedRectangle(cornerRadius: 28, style: .continuous)

    /// Fully circular shape. Use for icon buttons and avatars.
    static let full = Capsule()
}
