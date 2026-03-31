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
    static var checklistCompletedTextColor: UIColor { .secondaryLabel }
    static var inlineCodeBackgroundColor: UIColor { .secondarySystemFill }
    static var codeBlockBackgroundColor: UIColor { .secondarySystemBackground }
    static var codeBlockCornerRadius: CGFloat { 10 }
    static var codeBlockVerticalPadding: CGFloat { 8 }

    static func backgroundColor(
        for blockType: NotesSemanticDocument.BlockType,
        inlineCode: Bool
    ) -> UIColor? {
        if blockType == .codeBlock { return nil }
        return inlineCode ? inlineCodeBackgroundColor : nil
    }
    #elseif canImport(AppKit)
    static var caretTintColor: NSColor { .secondaryLabelColor }
    static var checklistCompletedTextColor: NSColor { .secondaryLabelColor }
    static var inlineCodeBackgroundColor: NSColor { .quaternaryLabelColor.withAlphaComponent(0.18) }
    static var codeBlockBackgroundColor: NSColor {
        NSColor(name: NSColor.Name("notesCodeBlockBackground")) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
                return NSColor(srgbRed: 0.149, green: 0.149, blue: 0.149, alpha: 1)
            }
            return NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1)
        }
    }
    static var codeBlockCornerRadius: CGFloat { 10 }
    static var codeBlockVerticalPadding: CGFloat { 8 }

    static func backgroundColor(
        for blockType: NotesSemanticDocument.BlockType,
        inlineCode: Bool
    ) -> NSColor? {
        if blockType == .codeBlock { return nil }
        return inlineCode ? inlineCodeBackgroundColor : nil
    }
    #endif
}
