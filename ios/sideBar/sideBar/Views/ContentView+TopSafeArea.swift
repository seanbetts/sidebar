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
