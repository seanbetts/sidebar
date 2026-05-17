import sideBarShared

#if canImport(UIKit)
import UIKit

extension UIImage {
    convenience init?(appIcon: AppIcon) {
        self.init(systemName: appIcon.rawValue)
    }
}
#endif

#if canImport(AppKit)
import AppKit

extension NSImage {
    convenience init?(appIcon: AppIcon, accessibilityDescription: String? = nil) {
        self.init(systemSymbolName: appIcon.rawValue, accessibilityDescription: accessibilityDescription)
    }
}
#endif
