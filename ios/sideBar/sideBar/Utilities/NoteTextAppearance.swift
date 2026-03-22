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

    static func backgroundColor(
        for blockType: NotesSemanticDocument.BlockType,
        inlineCode: Bool
    ) -> UIColor? {
        _ = blockType
        return inlineCode ? inlineCodeBackgroundColor : nil
    }
    #elseif canImport(AppKit)
    static var caretTintColor: NSColor { .secondaryLabelColor }
    static var inlineCodeBackgroundColor: NSColor { .quaternaryLabelColor.withAlphaComponent(0.18) }

    static func backgroundColor(
        for blockType: NotesSemanticDocument.BlockType,
        inlineCode: Bool
    ) -> NSColor? {
        _ = blockType
        return inlineCode ? inlineCodeBackgroundColor : nil
    }
    #endif
}
