import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum NoteFormattingBarChrome {
    static let entryControlKind: GlassChrome.Kind = .actionButton
    static let entryControlChromeStyle: HeaderActionControlChromeStyle = .glass
    static let entrySymbolPointSize: CGFloat = HeaderActionControlMetrics.symbolPointSize
    static let entryControlWidth: CGFloat = HeaderActionControlMetrics.chromeWidth
    static let entryControlHeight: CGFloat = HeaderActionControlMetrics.chromeHeight

    static func cornerRadius(for barHeight: CGFloat) -> CGFloat {
        _ = barHeight
        return DesignTokens.Radius.sm
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
struct NoteFormattingBar: View {
    let configuration: NoteFormattingBarConfiguration

    var body: some View {
        HeaderActionMenuControl(
            systemName: "textformat",
            accessibilityLabel: "Formatting",
            chromeStyle: NoteFormattingBarChrome.entryControlChromeStyle
        ) {
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
        }
        .disabled(!configuration.isEnabled)
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
