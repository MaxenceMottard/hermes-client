import PhotosUI
import SwiftUI

/// Sheet opened by the composer's add button: the recent photos in one row, where a tap adds or
/// removes a photo, then a list with "Camera" (iPhone and iPad with a camera) and "Photos", which
/// opens the whole library.
///
/// Both pickers edit the same `selection`, so a photo picked in one shows as picked in the other.
/// The embedded picker runs out of process: it needs no photo library permission.
struct AddToMessageSheet: View {
    @Binding var selection: [PhotosPickerItem]
    let maxSelectionCount: Int
    /// `false` once the message holds as many images as it can: the camera row is disabled.
    let canAddPhoto: Bool
    /// Called with the JPEG data of a photo taken with the camera.
    let onPhotoTaken: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isBrowsingLibrary = false
    @State private var isTakingPhoto = false
    /// The selection when the whole library opened, to close this sheet too once photos were picked there.
    @State private var selectionBeforeLibrary: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    if CameraPicker.isAvailable {
                        Button {
                            isTakingPhoto = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                        }
                        .disabled(!canAddPhoto)
                    }

                    Button {
                        selectionBeforeLibrary = selection
                        isBrowsingLibrary = true
                    } label: {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Add to message")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
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
            #if os(iOS)
                .fullScreenCover(isPresented: $isTakingPhoto) {
                    CameraPicker { data in
                        isTakingPhoto = false
                        if let data {
                            onPhotoTaken(data)
                            dismiss()
                        }
                    }
                    .ignoresSafeArea()
                }
            #endif
        }
        .presentationDetents([.height(CameraPicker.isAvailable ? 360 : 310)])
        .presentationDragIndicator(.visible)
    }
}
