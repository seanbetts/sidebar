import Foundation
import Combine

public final class ThemeManager: ObservableObject {
    @Published public var mode: ThemeMode {
        didSet {
            userDefaults.set(mode.rawValue, forKey: AppStorageKeys.themeMode)
        }
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: AppStorageKeys.themeMode),
           let stored = ThemeMode(rawValue: raw) {
            self.mode = stored
        } else {
            self.mode = .system
        }
    }
}
