import Foundation

@available(iOS 26.0, macOS 26.0, *)
/// Supported block-level text styles for rich note editing.
public enum NoteTextStyle: String, CaseIterable, Equatable {
    case body
    case title
    case heading
    case subheading

    var displayName: String {
        switch self {
        case .body:
            return "Body"
        case .title:
            return "Title"
        case .heading:
            return "Heading"
        case .subheading:
            return "Subhead"
        }
    }

    var blockType: NotesSemanticDocument.BlockType {
        switch self {
        case .body:
            return .paragraph
        case .title:
            return .title
        case .heading:
            return .heading
        case .subheading:
            return .subheading
        }
    }

    init?(blockType: NotesSemanticDocument.BlockType) {
        switch blockType {
        case .paragraph:
            self = .body
        case .title:
            self = .title
        case .heading:
            self = .heading
        case .subheading:
            self = .subheading
        default:
            return nil
        }
    }
}
