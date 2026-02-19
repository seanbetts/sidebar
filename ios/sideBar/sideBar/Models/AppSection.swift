import Foundation

public enum AppSection: String, CaseIterable, Identifiable {
    case chat
    case notes
    case files
    case websites
    case settings
    case tasks

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    public static let primaryNavigationSections: [AppSection] = [
        .chat,
        .notes,
        .tasks,
        .websites,
        .files
    ]
}
