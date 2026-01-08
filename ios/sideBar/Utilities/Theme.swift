import Foundation

public enum ThemeMode: String, Codable {
    case light
    case dark
}

public struct ThemeState: Codable {
    public let mode: ThemeMode

    public init(mode: ThemeMode) {
        self.mode = mode
    }
}
