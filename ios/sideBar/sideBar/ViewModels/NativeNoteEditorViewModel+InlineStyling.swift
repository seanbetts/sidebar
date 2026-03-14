import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func inlineStyledFont(bold: Bool, italic: Bool, monospaced: Bool) -> Font {
        noteInlineFont(
            baseFontSize: baseFontSize,
            bold: bold,
            italic: italic,
            monospaced: monospaced
        )
    }

    func inlineStyledPlatformFont(
        bold: Bool,
        italic: Bool,
        monospaced: Bool
    ) -> NotePlatformFont {
        notePlatformFont(
            baseFontSize: baseFontSize,
            bold: bold,
            italic: italic,
            monospaced: monospaced
        )
    }
}
