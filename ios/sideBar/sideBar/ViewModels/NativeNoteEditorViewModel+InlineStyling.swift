import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func inlineStyledFont(bold: Bool, italic: Bool) -> Font {
        noteInlineFont(baseFontSize: baseFontSize, bold: bold, italic: italic)
    }
}
