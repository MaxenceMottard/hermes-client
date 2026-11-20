import SwiftUI

#if os(iOS)
    import UIKit

    /// The system camera, full screen. Calls `onFinish` with the JPEG data of the photo taken, or `nil`
    /// when the user cancels.
    struct CameraPicker: UIViewControllerRepresentable {
        /// `false` on devices without a camera, such as the simulator.
        static var isAvailable: Bool {
            UIImagePickerController.isSourceTypeAvailable(.camera)
        }

        let onFinish: (Data?) -> Void

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(onFinish: onFinish)
        }

        @MainActor
        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let onFinish: (Data?) -> Void

            init(onFinish: @escaping (Data?) -> Void) {
                self.onFinish = onFinish
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                let image = info[.originalImage] as? UIImage
                onFinish(image?.jpegData(compressionQuality: 0.9))
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                onFinish(nil)
            }
        }
    }
#else
    /// macOS has no camera picker: the camera row is hidden.
    enum CameraPicker {
        static let isAvailable = false
    }
#endif
