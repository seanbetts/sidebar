import Foundation

#if canImport(UIKit)
import UIKit

func shareJPEGData(from image: SharePlatformImage, compressionQuality: CGFloat) -> Data? {
    image.jpegData(compressionQuality: compressionQuality)
}
#elseif canImport(AppKit)
import AppKit

func shareJPEGData(from image: SharePlatformImage, compressionQuality: CGFloat) -> Data? {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        return nil
    }

    let quality = max(0, min(1, compressionQuality))
    let properties: [NSBitmapImageRep.PropertyKey: Any] = [
        .compressionFactor: quality
    ]
    return bitmap.representation(using: .jpeg, properties: properties)
}
#endif
