#if os(macOS)
import Foundation

enum MacWindowFramePersistence {
    nonisolated static func unstableGeneratedFrameKeys(in defaultsDomain: [String: Any]) -> [String] {
        defaultsDomain.keys.filter(isUnstableGeneratedFrameKey).sorted()
    }

    static func purgeGeneratedSwiftUIWindowFrames(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        guard let bundleIdentifier else { return }
        guard var defaultsDomain = defaults.persistentDomain(forName: bundleIdentifier) else { return }

        let generatedKeys = unstableGeneratedFrameKeys(in: defaultsDomain)
        guard !generatedKeys.isEmpty else { return }

        for key in generatedKeys {
            defaultsDomain.removeValue(forKey: key)
        }

        defaults.setPersistentDomain(defaultsDomain, forName: bundleIdentifier)
    }

    nonisolated private static func isUnstableGeneratedFrameKey(_ key: String) -> Bool {
        key.hasPrefix("NSWindow Frame SwiftUI.") && key.hasSuffix("-AppWindow-1")
    }
}
#endif
