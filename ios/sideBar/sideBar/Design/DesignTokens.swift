import SwiftUI

enum DesignTokens {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Size {
        static let touchTarget: CGFloat = 44
        static let sidebarWidth: CGFloat = 280
        static let panelMinWidth: CGFloat = 320
        static let contentMaxWidth: CGFloat = 520
    }

    enum Icon {
        static let sm: CGFloat = 14
        static let md: CGFloat = 18
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
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
        static let warning = Color.yellow.opacity(0.2)
    }

    enum Animation {
        static let quick: Double = 0.15
        static let standard: Double = 0.25
        static let slow: Double = 0.4
    }
}
