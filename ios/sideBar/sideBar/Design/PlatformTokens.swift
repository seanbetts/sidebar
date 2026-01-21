import SwiftUI

enum PlatformTokens {
    static func panelHeaderBackground(_ colorScheme: ColorScheme) -> Color {
        #if os(macOS)
        if colorScheme == .light {
            return DesignTokens.Colors.sidebar
        }
        return DesignTokens.Colors.surface
        #else
        return DesignTokens.Colors.surface
        #endif
    }
}
