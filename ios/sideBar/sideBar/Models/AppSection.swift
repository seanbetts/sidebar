import Foundation

public enum AppSection: String, CaseIterable, Identifiable {
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

    public static let primaryNavigationSections: [AppSection] = [
        .chat,
        .notes,
        .tasks,
        .websites,
        .files,
        .skillsStore
    ]
}
