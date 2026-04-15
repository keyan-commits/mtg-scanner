import SwiftUI

/// A small `info.circle` button that, when tapped, shows a brief
/// explanation in a popover. Use this to clarify ambiguous terms,
/// status labels, or MTG jargon without cluttering the surrounding UI.
///
/// ```swift
/// HStack {
///     Text("Needed")
///     HelpButton("Cards you've added but haven't ordered yet")
/// }
/// ```
struct HelpButton: View {

    let text: String
    var size: CGFloat = 13

    @State private var showPopover = false

    init(_ text: String, size: CGFloat = 13) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(MD3Theme.onSurfaceVariant.opacity(0.7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            Text(text)
                .font(.callout)
                .foregroundStyle(MD3Theme.onSurface)
                .padding(14)
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
    }
}
