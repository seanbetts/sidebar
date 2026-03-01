import Foundation

@available(iOS 26.0, macOS 26.0, *)
/// Formatting actions available for native notes editing.
public enum NoteFormatting: Equatable {
    case bold
    case italic
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
extension NoteFormatting {
    var requiresStructuralRefresh: Bool {
        switch self {
        case .bold, .italic, .strikethrough, .inlineCode, .link:
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
}

@available(iOS 26.0, macOS 26.0, *)
public typealias MarkdownFormatting = NoteFormatting
