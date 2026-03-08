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
        case .skillsStore:
            return .contentBackground
        case .chat, .notes, .files, .websites, .tasks:
            return .panelChrome
        }
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
