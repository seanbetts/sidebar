import SwiftUI

enum PlatformTokens {
    enum SurfaceToken: Equatable {
        case background
        case sidebar

        var color: Color {
            switch self {
            case .background:
                return DesignTokens.Colors.background
            case .sidebar:
                return DesignTokens.Colors.sidebar
            }
        }
    }

    static func sidebarPanelBackgroundToken(isMacOS: Bool) -> SurfaceToken {
        _ = isMacOS
        return .sidebar
    }

    static var sidebarPanelBackground: Color {
        sidebarPanelBackgroundToken(isMacOS: runsOnMacOS).color
    }

    /// Background color for panel headers (title bar / search bar row).
    /// Uses an adaptive color that automatically resolves for light and dark mode.
    static var panelHeaderBackground: Color {
        sidebarPanelBackground
    }

    private static var runsOnMacOS: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }
}
