import SwiftUI

// MARK: - MD3 Card

/// A Material Design 3 filled card with tonal elevation and rounded shape.
struct MD3Card<Content: View>: View {

    let elevation: Int
    @ViewBuilder let content: () -> Content

    /// Creates a new MD3 card.
    /// - Parameters:
    ///   - elevation: Tonal elevation level (0-5). Defaults to 1.
    ///   - content: The card's content.
    init(elevation: Int = 1, @ViewBuilder content: @escaping () -> Content) {
        self.elevation = elevation
        self.content = content
    }

    var body: some View {
        content()
            .background(MD3Theme.surface)
            .md3Elevation(elevation)
            .clipShape(MD3Shape.medium)
            .overlay(
                MD3Shape.medium
                    .stroke(MD3Theme.outlineVariant, lineWidth: 1)
            )
    }
}

// MARK: - MD3 Filled Button

/// A Material Design 3 filled button using the primary color role.
struct MD3FilledButton: View {

    let title: String
    let action: () -> Void

    /// Creates a new MD3 filled button.
    /// - Parameters:
    ///   - title: The button label text.
    ///   - action: The action to perform when tapped.
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MD3Typography.labelLarge)
                .foregroundStyle(MD3Theme.onPrimary)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .frame(minHeight: 40)
                .background(MD3Theme.primary)
                .clipShape(MD3Shape.full)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MD3 Outlined Button

/// A Material Design 3 outlined button with a border stroke.
struct MD3OutlinedButton: View {

    let title: String
    let action: () -> Void

    /// Creates a new MD3 outlined button.
    /// - Parameters:
    ///   - title: The button label text.
    ///   - action: The action to perform when tapped.
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MD3Typography.labelLarge)
                .foregroundStyle(MD3Theme.primary)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .frame(minHeight: 40)
                .background(Color.clear)
                .clipShape(MD3Shape.full)
                .overlay(
                    Capsule()
                        .stroke(MD3Theme.outline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MD3 Top App Bar

/// A Material Design 3 small top app bar with title and optional navigation/action items.
struct MD3TopAppBar<LeadingContent: View, TrailingContent: View>: View {

    let title: String
    let leadingContent: LeadingContent
    let trailingContent: TrailingContent

    /// Creates a new MD3 top app bar.
    /// - Parameters:
    ///   - title: The title text displayed in the app bar.
    ///   - leading: Optional leading content (e.g., a back button).
    ///   - trailing: Optional trailing content (e.g., action icons).
    init(
        title: String,
        @ViewBuilder leading: () -> LeadingContent = { EmptyView() },
        @ViewBuilder trailing: () -> TrailingContent = { EmptyView() }
    ) {
        self.title = title
        self.leadingContent = leading()
        self.trailingContent = trailing()
    }

    var body: some View {
        HStack(spacing: 4) {
            leadingContent
                .frame(width: 48, height: 48)

            Text(title)
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onSurface)
                .lineLimit(1)

            Spacer()

            trailingContent
                .frame(height: 48)
        }
        .padding(.horizontal, 4)
        .frame(height: 64)
        .background(MD3Theme.surface)
        .md3Elevation(0)
    }
}
