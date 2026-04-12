#if os(macOS)
import AppKit
import Foundation

enum MacWindowFramePersistence {
    nonisolated static func autosaveKey(for autosaveName: String) -> String {
        "NSWindow Frame \(autosaveName)"
    }

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

    nonisolated static func windowFrameNeedsRecentering(
        _ windowFrame: CGRect,
        visibleScreenFrames: [CGRect]
    ) -> Bool {
        guard !visibleScreenFrames.isEmpty else { return false }
        return !visibleScreenFrames.contains { $0.intersects(windowFrame) }
    }

    nonisolated static func windowFrameNeedsPreferredScreenRelocation(
        _ windowFrame: CGRect,
        preferredVisibleScreenFrame: CGRect,
        visibleScreenFrames: [CGRect],
        enforcePreferredScreen: Bool
    ) -> Bool {
        if windowFrameNeedsRecentering(windowFrame, visibleScreenFrames: visibleScreenFrames) {
            return true
        }

        guard enforcePreferredScreen else { return false }
        return !preferredVisibleScreenFrame.intersects(windowFrame)
    }

    nonisolated static func centeredWindowFrame(
        for windowFrame: CGRect,
        in visibleScreenFrame: CGRect
    ) -> CGRect {
        let originX = visibleScreenFrame.origin.x + (visibleScreenFrame.width - windowFrame.width) / 2
        let originY = visibleScreenFrame.origin.y + (visibleScreenFrame.height - windowFrame.height) / 2
        return CGRect(origin: CGPoint(x: originX, y: originY), size: windowFrame.size)
    }

    nonisolated static func preferredVisibleScreenFrameForLateWindowRepair(
        mouseLocation: CGPoint,
        screenFrames: [CGRect],
        mainVisibleScreenFrame: CGRect?
    ) -> CGRect? {
        if let screenUnderMouse = screenFrames.first(where: { $0.contains(mouseLocation) }) {
            return screenUnderMouse
        }

        if let mainVisibleScreenFrame {
            return mainVisibleScreenFrame
        }

        return screenFrames.first
    }

    nonisolated static func shouldRestoreSavedWindowFrame(
        isVisible: Bool,
        isKeyWindow: Bool,
        isMainWindow: Bool
    ) -> Bool {
        !(isVisible || isKeyWindow || isMainWindow)
    }

    nonisolated static func savedWindowFrame(
        autosaveName: String,
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> CGRect? {
        guard let bundleIdentifier else { return nil }
        guard
            let defaultsDomain = defaults.persistentDomain(forName: bundleIdentifier),
            let serializedFrame = defaultsDomain[autosaveKey(for: autosaveName)] as? String
        else {
            return nil
        }

        let components = serializedFrame
            .split(whereSeparator: \.isWhitespace)
            .prefix(4)
            .compactMap { Double($0) }

        guard components.count == 4 else { return nil }

        return CGRect(
            x: components[0],
            y: components[1],
            width: components[2],
            height: components[3]
        )
    }

    nonisolated static func preferredLaunchWindowSize(
        savedWindowFrame: CGRect?,
        fallbackSize: CGSize
    ) -> CGSize {
        guard let savedWindowFrame else { return fallbackSize }
        guard savedWindowFrame.width > 0, savedWindowFrame.height > 0 else {
            return fallbackSize
        }

        return CGSize(width: savedWindowFrame.width, height: savedWindowFrame.height)
    }

    @MainActor
    static func restoreSavedWindowFrameIfNeeded(
        _ window: NSWindow,
        autosaveName: String? = nil,
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        let resolvedAutosaveName = autosaveName ?? MacWindowConfiguration.mainWindowID
        guard let savedFrame = savedWindowFrame(
            autosaveName: resolvedAutosaveName,
            defaults: defaults,
            bundleIdentifier: bundleIdentifier
        ) else {
            return false
        }

        let autosave = NSWindow.FrameAutosaveName(resolvedAutosaveName)
        if window.frameAutosaveName != autosave {
            window.setFrameAutosaveName(autosave)
        }
        window.setFrame(savedFrame, display: false)
        return true
    }

    @MainActor
    static func recenterWindowIfNeeded(
        _ window: NSWindow,
        preferredScreen: NSScreen? = NSScreen.main,
        screens: [NSScreen] = NSScreen.screens,
        preferredVisibleScreenFrame: CGRect? = nil,
        enforcePreferredScreen: Bool = false
    ) -> Bool {
        let visibleFrames = screens.map(\.visibleFrame)
        guard let targetVisibleFrame = preferredVisibleScreenFrame ?? (preferredScreen ?? screens.first)?.visibleFrame else {
            return false
        }

        guard windowFrameNeedsPreferredScreenRelocation(
            window.frame,
            preferredVisibleScreenFrame: targetVisibleFrame,
            visibleScreenFrames: visibleFrames,
            enforcePreferredScreen: enforcePreferredScreen
        ) else {
            return false
        }

        window.setFrame(centeredWindowFrame(for: window.frame, in: targetVisibleFrame), display: false)
        return true
    }

    @MainActor
    static func persistWindowFrameIfNeeded(
        _ window: NSWindow,
        autosaveName: String? = nil
    ) {
        let autosave = NSWindow.FrameAutosaveName(autosaveName ?? MacWindowConfiguration.mainWindowID)
        if window.frameAutosaveName != autosave {
            window.setFrameAutosaveName(autosave)
        }
        window.saveFrame(usingName: autosave)
    }
}
#endif
