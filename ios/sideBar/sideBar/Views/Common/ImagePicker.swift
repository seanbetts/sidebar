import SwiftUI

#if os(iOS)
import UIKit
import UniformTypeIdentifiers

private struct ImageUploadPayload {
    let data: Data
    let contentType: String
    let filename: String
}

public struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: Image?
    private let onImageDataPicked: ((Data, String, String) -> Void)?

    public init(
        selectedImage: Binding<Image?>,
        onImageDataPicked: ((Data, String, String) -> Void)? = nil
    ) {
        self._selectedImage = selectedImage
        self.onImageDataPicked = onImageDataPicked
    }

    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        public func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            if let image {
                parent.selectedImage = Image(uiImage: image)
                if let payload = makeUploadPayload(image: image, info: info) {
                    parent.onImageDataPicked?(payload.data, payload.contentType, payload.filename)
                }
            }
            picker.dismiss(animated: true)
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        private func makeUploadPayload(
            image: UIImage,
            info: [UIImagePickerController.InfoKey: Any]
        ) -> ImageUploadPayload? {
            if let imageUrl = info[.imageURL] as? URL,
               let data = try? Data(contentsOf: imageUrl) {
                let contentType = UTType(filenameExtension: imageUrl.pathExtension)?.preferredMIMEType
                    ?? "image/jpeg"
                let filename = imageUrl.lastPathComponent.isEmpty
                    ? "profile-image.jpg"
                    : imageUrl.lastPathComponent
                return ImageUploadPayload(data: data, contentType: contentType, filename: filename)
            }
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                return nil
            }
            return ImageUploadPayload(
                data: data,
                contentType: "image/jpeg",
                filename: "profile-image.jpg"
            )
        }
    }
}
#endif
