import SwiftUI

extension NotesDetailView {
    #if os(iOS)
    var noteFormattingBarConfiguration: NoteFormattingBarConfiguration {
        if #available(iOS 26.0, *) {
            return editorViewModel.noteFormattingBarConfiguration
        }
        return .disabled
    }

    var noteFormattingBar: some View {
        let configuration = noteFormattingBarConfiguration

        return UIKitNoteFormattingBarRepresentable(
            configuration: configuration,
            presentation: formattingBarPresentation
        )
        .disabled(!configuration.isEnabled)
    }
    #endif
}
