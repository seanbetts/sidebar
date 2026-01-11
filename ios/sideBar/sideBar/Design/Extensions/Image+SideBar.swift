import SwiftUI

extension Image {
    static func fromProfileData(_ data: Data) -> Image? {
        #if os(macOS)
        if let image = NSImage(data: data) {
            return Image(nsImage: image)
        }
        #else
        if let image = UIImage(data: data) {
            return Image(uiImage: image)
        }
        #endif
        return nil
    }
}
