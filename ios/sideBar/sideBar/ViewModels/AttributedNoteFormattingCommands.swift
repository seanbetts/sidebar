import Foundation

@MainActor
@available(iOS 26.0, macOS 26.0, *)
enum AttributedNoteFormattingCommands {
    static func apply(_ formatting: NoteFormatting, on viewModel: NativeNoteEditorViewModel) {
        switch formatting {
        case .bold:
            viewModel.toggleInlineIntent(.stronglyEmphasized)
        case .italic:
            viewModel.toggleInlineIntent(.emphasized)
        case .underline:
            viewModel.toggleUnderline()
        }
    }
}
