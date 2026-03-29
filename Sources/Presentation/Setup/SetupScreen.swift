import SwiftUI

// MARK: - Setup State

enum SetupState: Equatable {
    case checking
    case downloading
    case importing(progress: Double)
    case ready
    case error(String)
}

// MARK: - Setup Screen

/// First-launch screen that downloads the Scryfall bulk card database.
struct SetupScreen: View {

    @Binding var setupState: SetupState

    var body: some View {
        ZStack {
            MD3Theme.background
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(MD3Theme.primary)

                Text("MTG Card Identifier")
                    .font(MD3Typography.headlineLarge)
                    .foregroundStyle(MD3Theme.onBackground)

                statusView

                Spacer()
            }
            .padding(32)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch setupState {
        case .checking:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(MD3Theme.primary)
                Text("Checking card database...")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

        case .downloading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(MD3Theme.primary)
                Text("Downloading card database...")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                Text("This may take a moment (~25 MB)")
                    .font(MD3Typography.labelMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

        case .importing(let progress):
            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .tint(MD3Theme.primary)
                    .padding(.horizontal, 48)
                Text("Importing cards... \(Int(progress * 100))%")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

        case .ready:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
                Text("Database ready!")
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
            }

        case .error(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(MD3Theme.error)
                Text(message)
                    .font(MD3Typography.bodyMedium)
                    .foregroundStyle(MD3Theme.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
