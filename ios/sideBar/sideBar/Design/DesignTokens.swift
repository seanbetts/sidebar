import SwiftUI

enum DesignTokens {
    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xxsPlus: CGFloat = 6
        static let xs: CGFloat = 8
        static let xsPlus: CGFloat = 10
        static let sm: CGFloat = 12
        static let smPlus: CGFloat = 14
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let xs: CGFloat = 6
        static let xsPlus: CGFloat = 8
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let mdPlus: CGFloat = 16
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Size {
        static let touchTarget: CGFloat = 44
        static let compactFieldHeight: CGFloat = 40
        static let sidebarWidth: CGFloat = 280
        static let railWidth: CGFloat = 56
        static let dividerWidth: CGFloat = 8
        static let rightSidebarDefaultWidth: CGFloat = 360
        static let panelMinWidth: CGFloat = 320
        static let contentMaxWidth: CGFloat = 520
        static let inspectorMaxWidth: CGFloat = 1_120
    }

    enum Icon {
        static let sm: CGFloat = 14
        static let md: CGFloat = 18
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
        static let hero: CGFloat = 64
    }

    enum Colors {
        static let background = Color.appBackground
        static let surface = Color.appSurface
        static let muted = Color.appMuted
        static let sidebar = Color.appSidebar
        static let sidebarAccent = Color.appSidebarAccent
        static let border = Color.appBorder
        static let input = Color.appInput
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.platformTertiaryLabel
        static let selection = Color.appSelection
        static let success = Color(red: 0.13, green: 0.55, blue: 0.28)
        static let successBackground = success.opacity(0.16)
        static let successBorder = success.opacity(0.34)
        static let warning = Color(red: 0.85, green: 0.47, blue: 0.02)
        static let warningBackground = Color(red: 0.98, green: 0.75, blue: 0.14).opacity(0.16)
        static let warningBorder = warning.opacity(0.34)
        static let error = Color.red
        static let errorBackground = Color.red.opacity(0.1)
        static let errorSurface = Color.red.opacity(0.12)
        static let errorBorder = Color.red.opacity(0.2)
        static let actionPrimary = Color.blue
        static let actionDestructive = Color.red

        /// Outer chrome/wrapper for settings panels.
        static let settingsBackground = Color.appSettingsBackground
        /// Inner form/list surface for settings panels.
        static let settingsFormBackground = Color.appSettingsFormBackground
        static let sidebarHoverBackground = selection.opacity(0.42)

        static var sidebarRowBackground: Color {
            .clear
        }

        static func sidebarRowBackground(isSelected: Bool) -> Color {
            isSelected ? selection : sidebarRowBackground
        }
    }

    enum Animation {
        static let quick: Double = 0.15
        static let standard: Double = 0.25
        static let slow: Double = 0.4
    }

}
