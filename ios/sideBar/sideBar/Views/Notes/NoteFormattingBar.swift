import SwiftUI

#if os(iOS)
@MainActor
@available(iOS 26.0, *)
struct NoteFormattingBar: View {
    let configuration: NoteFormattingBarConfiguration

    var body: some View {
        Menu {
            Section("Text Style") {
                ForEach(NoteTextStyle.allCases, id: \.self) { style in
                    Button {
                        configuration.selectTextStyle(style)
                    } label: {
                        if configuration.activeTextStyle == style {
                            Label(style.displayName, systemImage: "checkmark")
                        } else {
                            Text(style.displayName)
                        }
                    }
                    .disabled(!configuration.canApplyTextStyle(style))
                }
            }

            Section("Inline") {
                inlineButton("Bold", formatting: .bold)
                inlineButton("Italic", formatting: .italic)
                inlineButton("Underline", formatting: .underline)
                inlineButton("Strikethrough", formatting: .strikethrough)
                inlineButton("Inline Code", formatting: .inlineCode)
            }
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!configuration.isEnabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .accessibilityIdentifier("note-formatting-bar")
    }

    @ViewBuilder
    private func inlineButton(_ title: String, formatting: NoteFormatting) -> some View {
        Button {
            configuration.tapHandler(for: formatting)()
        } label: {
            if configuration.isActive(formatting) {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
#endif
