import Foundation

@available(iOS 26.0, macOS 26.0, *)
/// Formatting actions available for native notes editing.
public enum NoteFormatting: Equatable {
    case bold
    case italic
    case underline
}

@available(iOS 26.0, macOS 26.0, *)
enum NoteFormattingCapability: Hashable {
    case bold
    case italic
    case underline
}

@available(iOS 26.0, macOS 26.0, *)
extension NoteFormatting {
    var runtimeCapability: NoteFormattingCapability? {
        switch self {
        case .bold:
            return .bold
        case .italic:
            return .italic
        case .underline:
            return .underline
        }
    }
}
