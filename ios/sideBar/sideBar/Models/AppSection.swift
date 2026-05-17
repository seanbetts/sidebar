import Foundation
import sideBarShared

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

    public var appIcon: AppIcon {
        switch self {
        case .chat:
            return AppIcon.Domain.chat
        case .notes:
            return AppIcon.Domain.notes
        case .files:
            return AppIcon.Domain.files
        case .websites:
            return AppIcon.Domain.websites
        case .skillsStore:
            return AppIcon.Domain.skillsStore
        case .settings:
            return AppIcon.Domain.settings
        case .tasks:
            return AppIcon.Domain.tasks
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
