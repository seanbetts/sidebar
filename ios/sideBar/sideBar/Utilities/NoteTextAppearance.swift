import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextAppearance {
    #if canImport(UIKit)
    static var caretTintColor: UIColor { .secondaryLabel }
    static var inlineCodeBackgroundColor: UIColor { .secondarySystemFill }
    #elseif canImport(AppKit)
    static var inlineCodeBackgroundColor: NSColor { .quaternaryLabelColor.withAlphaComponent(0.18) }
    #endif
}
