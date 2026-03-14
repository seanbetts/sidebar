import Foundation

@available(iOS 26.0, macOS 26.0, *)
/// Formatting actions available for native notes editing.
public enum NoteFormatting: Equatable {
    case bold
    case italic
    case underline
    case strikethrough
    case inlineCode
}
