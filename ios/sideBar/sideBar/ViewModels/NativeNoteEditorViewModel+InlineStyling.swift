import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    func inlineStyledFont(
        blockKind: BlockKind?,
        bold: Bool,
        italic: Bool
    ) -> Font {
        var font = baseFont(for: blockKind)
        if bold {
            font = font.weight(.bold)
        }
        if italic {
            font = font.italic()
        }
        return font
    }
}
