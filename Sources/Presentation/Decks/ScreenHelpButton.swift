import SwiftUI

/// One section in a per-screen help sheet. Shows an SF Symbol, a short
/// title, and a one-paragraph body.
struct HelpSection: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
}

/// Toolbar button that opens a focused, screen-specific help sheet.
/// Use this on each major screen so the user can get just-in-time guidance
/// without leaving for the global "How it works" screen.
///
/// Example:
/// ```swift
/// .toolbar {
///     ToolbarItem(placement: .topBarTrailing) {
///         ScreenHelpButton(
///             title: "My Decks",
///             sections: [
///                 HelpSection(icon: "plus", title: "Create",
///                             body: "Tap + to make a new deck."),
///                 HelpSection(icon: "pencil", title: "Edit",
///                             body: "Swipe right to rename or change format."),
///             ]
///         )
///     }
/// }
/// ```
struct ScreenHelpButton: View {

    let title: String
    let sections: [HelpSection]

    @State private var showSheet: Bool = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .sheet(isPresented: $showSheet) {
            ScreenHelpSheet(title: title, sections: sections)
                .presentationDetents([.medium, .large])
        }
    }
}

/// The sheet content. Internal so it can be presented from
/// `ScreenHelpButton`. Each section is rendered as a card with icon + title
/// + body.
private struct ScreenHelpSheet: View {

    let title: String
    let sections: [HelpSection]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        sectionCard(section)
                    }
                }
                .padding(20)
            }
            .background(MD3Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionCard(_ section: HelpSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.body)
                    .foregroundStyle(MD3Theme.primary)
                    .frame(width: 22)
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MD3Theme.onSurface)
            }
            Text(section.body)
                .font(.callout)
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 32)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MD3Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MD3Theme.outlineVariant, lineWidth: 1)
        )
    }
}
