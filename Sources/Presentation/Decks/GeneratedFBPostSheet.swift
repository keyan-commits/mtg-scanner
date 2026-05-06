import SwiftUI
import UIKit

/// Read-only preview of the generated FB sale post for the selected
/// listings. Copy button puts the full post text on the clipboard so
/// the user can paste it directly into Facebook.
///
/// Editable on purpose — the user often wants to nudge a price or
/// drop a line before posting. Edits don't affect the underlying
/// listings; this is one-shot text only.
struct GeneratedFBPostSheet: View {
    let initialText: String
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var showCopiedToast: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                if showCopiedToast {
                    Text("Copied to clipboard")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.85))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("FB Post Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onClose()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIPasteboard.general.string = text
                        withAnimation { showCopiedToast = true }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation { showCopiedToast = false }
                        }
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .bold()
                }
            }
        }
        .onAppear { text = initialText }
    }
}
