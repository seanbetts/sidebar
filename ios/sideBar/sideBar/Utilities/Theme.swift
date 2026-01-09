import Foundation

public enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

public struct ThemeState: Codable {
    public let mode: ThemeMode

    public init(mode: ThemeMode) {
        self.mode = mode
    }
}
