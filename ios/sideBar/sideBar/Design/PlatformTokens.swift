import SwiftUI

enum PlatformTokens {
    /// Background color for panel headers (title bar / search bar row).
    /// Uses an adaptive color that automatically resolves for light and dark mode.
    static var panelHeaderBackground: Color {
        DesignTokens.Colors.sidebar
    }
}
