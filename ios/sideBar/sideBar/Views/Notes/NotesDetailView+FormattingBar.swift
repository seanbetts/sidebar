import SwiftUI

extension NotesDetailView {
    var noteFormattingBarConfiguration: NoteFormattingBarConfiguration {
        if #available(iOS 26.0, macOS 26.0, *) {
            return editorViewModel.noteFormattingBarConfiguration
        }
        return .disabled
    }

    var noteFormattingBar: some View {
        let configuration = noteFormattingBarConfiguration

        #if os(iOS)
        return UIKitNoteFormattingBarRepresentable(
            configuration: configuration,
            presentation: formattingBarPresentation
        )
        .disabled(!configuration.isEnabled)
        #elseif os(macOS)
        return AppKitNoteFormattingOverlay(
            configuration: configuration,
            presentation: formattingBarPresentation
        )
        #endif
    }
}
