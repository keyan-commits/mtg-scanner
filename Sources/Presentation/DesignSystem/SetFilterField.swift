import SwiftUI

/// Reusable filter bar for narrowing a printings list by set name or set code.
/// Shown above any printing-selection list (Correct Card, Change Printing,
/// Pick Printing, Add Card, Add to Collection).
struct SetFilterField: View {
    @Binding var text: String
    var placeholder: String = "Filter by set name or code…"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(MD3Theme.onSurfaceVariant)
                .font(.caption)
            TextField(placeholder, text: $text)
                .font(MD3Typography.bodySmall)
                .foregroundStyle(MD3Theme.onSurface)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MD3Theme.onSurfaceVariant)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MD3Theme.surfaceVariant.opacity(0.5))
    }
}

extension Card {
    /// Case-insensitive substring match against set name OR set code.
    /// Empty / whitespace-only query returns true (no filter applied).
    func matchesSetFilter(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        return set.name.lowercased().contains(trimmed)
            || set.code.lowercased().contains(trimmed)
    }
}
