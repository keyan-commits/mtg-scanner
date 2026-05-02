import SwiftUI

/// Banner shown above MTGTop8-backed screens when the site is
/// unavailable. Communicates "we're showing you what we last saved"
/// without alarming the user or hiding the underlying staleness.
struct MTGTop8OutageBanner: View {
    let outageStartedAt: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.medium)
            VStack(alignment: .leading, spacing: 2) {
                Text("MTGTop8 unavailable")
                    .font(.subheadline.weight(.semibold))
                Text("Showing cached tournament data from \(outageStartedAt.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(Color.orange.opacity(0.4))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

/// View modifier — call `.mtgTop8OutageBanner()` on any screen that
/// surfaces MTGTop8-backed data. Renders the banner above the content
/// when the monitor reports unavailability and silently disappears
/// otherwise.
struct MTGTop8OutageBannerModifier: ViewModifier {
    @State private var state = MTGTop8AvailabilityState.shared

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if !state.isAvailable, let outageStart = state.outageStartedAt {
                MTGTop8OutageBanner(outageStartedAt: outageStart)
            }
            content
        }
        .task {
            // Initial sync, then poll every 5s while the screen is
            // visible. SwiftUI cancels this when the view disappears.
            while !Task.isCancelled {
                await state.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

extension View {
    /// Surfaces the MTGTop8 outage banner above this view when the
    /// site is unavailable. Banner disappears automatically when
    /// MTGTop8 comes back.
    func mtgTop8OutageBanner() -> some View {
        modifier(MTGTop8OutageBannerModifier())
    }
}
