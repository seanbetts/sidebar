import Foundation

public enum ShortcutContext: String, CaseIterable, Identifiable {
    case universal
    case chat
    case notes
    case notesEditing
    case websites
    case files
    case tasks

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .universal:
            return "Universal"
        case .chat:
            return "Chat"
        case .notes:
            return "Notes"
        case .notesEditing:
            return "Notes Editing"
        case .websites:
            return "Websites"
        case .files:
            return "Files"
        case .tasks:
            return "Tasks"
        }
    }

    public static func from(section: AppSection) -> ShortcutContext {
        switch section {
        case .chat:
            return .chat
        case .notes:
            return .notes
        case .files:
            return .files
        case .websites:
            return .websites
        case .tasks:
            return .tasks
        case .settings:
            return .universal
        }
    }
}
