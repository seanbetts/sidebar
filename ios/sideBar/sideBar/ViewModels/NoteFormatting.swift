import Foundation

@available(iOS 26.0, macOS 26.0, *)
/// Formatting actions available for native notes editing.
public enum NoteFormatting: Equatable {
    case bold
    case italic
    case underline
    case strikethrough
    case inlineCode
    case heading(level: Int)
    case promoteHeading
    case demoteHeading
    case bulletList
    case orderedList
    case taskList
    case indentList
    case outdentList
    case blockquote
    case codeBlock
    case link(URL)
    case horizontalRule
}

@available(iOS 26.0, macOS 26.0, *)
enum NoteFormattingCapability: Hashable {
    case bold
    case italic
    case underline
    case bulletList
}

@available(iOS 26.0, macOS 26.0, *)
extension NoteFormatting {
    var requiresStructuralRefresh: Bool {
        switch self {
        case .bold, .italic, .underline, .strikethrough, .inlineCode, .link:
            return false
        case .heading,
             .promoteHeading,
             .demoteHeading,
             .bulletList,
             .orderedList,
             .taskList,
             .indentList,
             .outdentList,
             .blockquote,
             .codeBlock,
             .horizontalRule:
            return true
        }
    }

    var runtimeCapability: NoteFormattingCapability? {
        switch self {
        case .bold:
            return .bold
        case .italic:
            return .italic
        case .underline:
            return .underline
        case .bulletList:
            return .bulletList
        default:
            return nil
        }
    }
}
