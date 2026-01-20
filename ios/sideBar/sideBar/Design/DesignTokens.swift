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
        static let error = Color.red
        static let errorBackground = Color.red.opacity(0.1)
        static let errorSurface = Color.red.opacity(0.12)
        static let errorBorder = Color.red.opacity(0.2)
    }

    enum Animation {
        static let quick: Double = 0.15
        static let standard: Double = 0.25
        static let slow: Double = 0.4
    }

    enum Typography {
        static let titleXL = Font.system(size: 32, weight: .semibold)
        static let display = Font.system(size: 32, weight: .regular)
        static let titleLg = Font.system(size: 18, weight: .semibold)
        static let titleMd = Font.system(size: 16, weight: .semibold)
        static let labelLg = Font.system(size: 15, weight: .semibold)
        static let labelMd = Font.system(size: 14, weight: .semibold)
        static let labelSm = Font.system(size: 13, weight: .semibold)
        static let labelXs = Font.system(size: 12, weight: .semibold)
        static let labelXxs = Font.system(size: 10, weight: .bold)
        static let monoLabel = Font.system(size: 14, weight: .semibold, design: .monospaced)
        static let monoBody = Font.system(.body, design: .monospaced)
        static let logo = Font.system(size: 60, weight: .regular)

        static let title2 = Font.title2
        static let title2Semibold = Font.title2.weight(.semibold)
        static let title3Semibold = Font.title3.weight(.semibold)
        static let headline = Font.headline
        static let headlineBold = Font.headline.weight(.bold)
        static let subheadline = Font.subheadline
        static let subheadlineSemibold = Font.subheadline.weight(.semibold)
        static let callout = Font.callout
        static let body = Font.body
        static let caption = Font.caption
        static let captionSemibold = Font.caption.weight(.semibold)
        static let caption2 = Font.caption2
        static let caption2Semibold = Font.caption2.weight(.semibold)
        static let footnote = Font.footnote
    }
}
