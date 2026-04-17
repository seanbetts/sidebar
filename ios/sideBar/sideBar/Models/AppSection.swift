import Foundation

public enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case chat
    case notes
    case files
    case websites
    case skillsStore
    case settings
    case tasks

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .skillsStore:
            return "Skills Store"
        default:
            return rawValue.capitalized
        }
    }

    public var iconName: String {
        switch self {
        case .chat:
            return "bubble"
        case .notes:
            return "text.document"
        case .files:
            return "folder"
        case .websites:
            return "globe"
        case .skillsStore:
            return "command.circle"
        case .settings:
            return "square.grid.2x2"
        case .tasks:
            return "checkmark.square"
        }
    }

    public static let primaryNavigationSections: [AppSection] = [
        .chat,
        .notes,
        .tasks,
        .websites,
        .files,
        .skillsStore
    ]
}
