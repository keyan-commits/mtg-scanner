import SwiftUI

/// Reusable empty state placeholder with icon, title, description, and optional action.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    let actionLabel: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        description: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(MD3Theme.primary.opacity(0.6))
            Text(title)
                .font(MD3Typography.titleLarge)
                .foregroundStyle(MD3Theme.onBackground)
            Text(description)
                .font(MD3Typography.bodyMedium)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(MD3Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
