import PhotosUI
import SwiftUI

/// Sheet opened by the composer's add button: the recent photos in one row, where a tap adds or
/// removes a photo, and a "Photos" button that opens the whole library.
///
/// Both pickers edit the same `selection`, so a photo picked in one shows as picked in the other.
/// The embedded picker runs out of process: it needs no photo library permission.
struct AddToMessageSheet: View {
    @Binding var selection: [PhotosPickerItem]
    let maxSelectionCount: Int

    @Environment(\.dismiss) private var dismiss
    @State private var isBrowsingLibrary = false
    /// The selection when the whole library opened, to close this sheet too once photos were picked there.
    @State private var selectionBeforeLibrary: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            PhotosPicker(
                selection: $selection,
                maxSelectionCount: maxSelectionCount,
                selectionBehavior: .continuousAndOrdered,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text("Recent photos")
            }
            .photosPickerStyle(.compact)
            .photosPickerDisabledCapabilities([.search, .collectionNavigation, .stagingArea, .selectionActions])
            #if os(iOS)
                .photosPickerAccessoryVisibility(.hidden, edges: .all)
            #endif
            .frame(height: 120)
            .padding(.horizontal)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Add to message")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Photos") {
                        selectionBeforeLibrary = selection
                        isBrowsingLibrary = true
                    }
                }
            }
            .photosPicker(
                isPresented: $isBrowsingLibrary,
                selection: $selection,
                maxSelectionCount: maxSelectionCount,
                selectionBehavior: .ordered,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: isBrowsingLibrary) { _, isOpen in
                if !isOpen, selection != selectionBeforeLibrary {
                    dismiss()
                }
            }
        }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }
}
