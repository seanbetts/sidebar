import SwiftUI
#if os(iOS)
import UIKit
#endif

extension ContentView {
    enum CompactPhoneTopSafeAreaStyle: Equatable {
        case panelChrome
        case settingsChrome
        case contentBackground

        var color: Color {
            switch self {
            case .panelChrome:
                return PlatformTokens.panelHeaderBackground
            case .settingsChrome:
                return DesignTokens.Colors.settingsBackground
            case .contentBackground:
                return DesignTokens.Colors.background
            }
        }
    }

    enum CompactPhonePanelBackgroundStyle: Equatable {
        case sidebar
        case settings
        case contentBackground

        var color: Color {
            switch self {
            case .sidebar:
                return DesignTokens.Colors.sidebar
            case .settings:
                return DesignTokens.Colors.settingsBackground
            case .contentBackground:
                return DesignTokens.Colors.background
            }
        }
    }

    struct CompactPhoneNavigationBarAppearanceStyle: Equatable {
        let backgroundStyle: CompactPhonePanelBackgroundStyle
        let isOpaque: Bool
    }

    static func shouldShowGlobalTopSafeAreaOverlay(
        isCompact: Bool,
        isPhoneIdiom: Bool
    ) -> Bool {
        !(isCompact && isPhoneIdiom)
    }

    static func compactPhoneRootTopSafeAreaStyle(for section: AppSection) -> CompactPhoneTopSafeAreaStyle {
        switch section {
        case .settings:
            return .settingsChrome
        case .chat, .notes, .files, .websites, .tasks, .skillsStore:
            return .panelChrome
        }
    }

    static func compactPhonePanelBackgroundStyle(for section: AppSection) -> CompactPhonePanelBackgroundStyle {
        switch section {
        case .settings:
            return .settings
        case .chat, .notes, .files, .websites, .tasks, .skillsStore:
            return .sidebar
        }
    }

    static func compactPhoneMoreRootTopSafeAreaStyle() -> CompactPhoneTopSafeAreaStyle {
        .panelChrome
    }

    static func compactPhoneMoreRootBackgroundStyle() -> CompactPhonePanelBackgroundStyle {
        .sidebar
    }

    static func compactPhoneMoreDestinationUsesDedicatedScaffold(for section: AppSection) -> Bool {
        switch section {
        case .files, .skillsStore:
            return true
        case .chat, .notes, .tasks, .websites, .settings:
            return false
        }
    }

    static func compactPhoneMoreDestinationBackgroundStyle(for section: AppSection) -> CompactPhonePanelBackgroundStyle {
        switch section {
        case .files, .skillsStore:
            return .sidebar
        case .settings:
            return .settings
        case .chat, .notes, .tasks, .websites:
            return compactPhonePanelBackgroundStyle(for: section)
        }
    }

    static func compactPhoneMoreDestinationTopSafeAreaStyle(for section: AppSection) -> CompactPhonePanelBackgroundStyle {
        compactPhoneMoreDestinationBackgroundStyle(for: section)
    }

    static func compactPhoneMoreDestinationNavigationBarAppearanceStyle(
        for section: AppSection
    ) -> CompactPhoneNavigationBarAppearanceStyle {
        CompactPhoneNavigationBarAppearanceStyle(
            backgroundStyle: compactPhoneMoreDestinationBackgroundStyle(for: section),
            isOpaque: true
        )
    }

    var shouldShowGlobalTopSafeAreaOverlay: Bool {
        #if os(macOS)
        return true
        #else
        return Self.shouldShowGlobalTopSafeAreaOverlay(
            isCompact: isCompact,
            isPhoneIdiom: isPhoneIdiom
        )
        #endif
    }

    var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
}
