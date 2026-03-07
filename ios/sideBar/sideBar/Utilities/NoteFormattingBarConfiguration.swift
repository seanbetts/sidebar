#if os(iOS)
import Foundation

@available(iOS 26.0, *)
struct NoteFormattingBarConfiguration {
    let isBoldActive: Bool
    let isItalicActive: Bool
    let isUnderlineActive: Bool
    let isEnabled: Bool
    let onBoldTap: @MainActor @Sendable () -> Void
    let onItalicTap: @MainActor @Sendable () -> Void
    let onUnderlineTap: @MainActor @Sendable () -> Void

    static let disabled = NoteFormattingBarConfiguration(
        isBoldActive: false,
        isItalicActive: false,
        isUnderlineActive: false,
        isEnabled: false,
        onBoldTap: {},
        onItalicTap: {},
        onUnderlineTap: {}
    )

    func isActive(_ formatting: NoteFormatting) -> Bool {
        switch formatting {
        case .bold:
            return isBoldActive
        case .italic:
            return isItalicActive
        case .underline:
            return isUnderlineActive
        }
    }

    func tapHandler(for formatting: NoteFormatting) -> @MainActor @Sendable () -> Void {
        switch formatting {
        case .bold:
            return onBoldTap
        case .italic:
            return onItalicTap
        case .underline:
            return onUnderlineTap
        }
    }
}
#endif
