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
        if formattingBarPresentation == .floatingTopTrailing {
            return AnyView(
                ZStack(alignment: .topTrailing) {
                    NoteFormattingBar(configuration: configuration)
                        .disabled(!configuration.isEnabled)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    UIKitNoteFormattingBarRepresentable(
                        configuration: configuration,
                        presentation: formattingBarPresentation,
                        showsVisibleChrome: false
                    )
                }
                    .disabled(!configuration.isEnabled)
            )
        }
        return AnyView(
            UIKitNoteFormattingBarRepresentable(
                configuration: configuration,
                presentation: formattingBarPresentation
            )
            .disabled(!configuration.isEnabled)
        )
        #elseif os(macOS)
        return AnyView(
            ZStack(alignment: .topTrailing) {
                NoteFormattingBar(configuration: configuration)
                    .disabled(!configuration.isEnabled)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                AppKitNoteFormattingOverlay(
                    configuration: configuration,
                    presentation: formattingBarPresentation,
                    showsVisibleChrome: false
                )
            }
                .disabled(!configuration.isEnabled)
        )
        #endif
    }
}
