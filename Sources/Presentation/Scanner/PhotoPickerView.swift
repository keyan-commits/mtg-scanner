import SwiftUI
import PhotosUI

// MARK: - Photo Picker View

/// A SwiftUI view that presents a multi-select photo picker for scanning MTG cards.
///
/// Wraps `PhotosPicker` from PhotosUI with MD3 styling and supports selecting
/// up to 20 card photos at once for batch processing.
struct PhotoPickerView: View {

    /// The selected photo items, bound to the parent view for processing.
    @Binding var selectedItems: [PhotosPickerItem]

    var body: some View {
        PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: 20,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label("Select Card Photos", systemImage: "photo.stack")
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
