import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
        static let success = textPrimary
        static let successBackground = muted.opacity(0.55)
        static let warning = textSecondary
        static let warningBackground = muted.opacity(0.55)
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

    enum Typography {
        static var titleXL: Font { .system(size: scaled(32), weight: .semibold) }
        static var display: Font { .system(size: scaled(32), weight: .regular) }
        static var titleLg: Font { .system(size: scaled(18), weight: .semibold) }
        static var titleMd: Font { .system(size: scaled(16), weight: .semibold) }
        static var labelLg: Font { .system(size: scaled(15), weight: .semibold) }
        static var labelMd: Font { .system(size: scaled(14), weight: .semibold) }
        static var labelSm: Font { .system(size: scaled(13), weight: .semibold) }
        static var labelXs: Font { .system(size: scaled(12), weight: .semibold) }
        static var labelXxs: Font { .system(size: scaled(10), weight: .bold) }
        static var monoLabel: Font { .system(size: scaled(14), weight: .semibold, design: .monospaced) }
        static var monoBody: Font { .system(size: bodyPointSize, weight: .regular, design: .monospaced) }
        static var logo: Font { .system(size: scaled(60), weight: .regular) }

        static var title2: Font { .system(size: title2PointSize, weight: .regular) }
        static var title2Semibold: Font { .system(size: title2PointSize, weight: .semibold) }
        static var title3Semibold: Font { .system(size: title3PointSize, weight: .semibold) }
        static var headline: Font { .system(size: headlinePointSize, weight: .regular) }
        static var headlineBold: Font { .system(size: headlinePointSize, weight: .bold) }
        static var subheadline: Font { .system(size: subheadlinePointSize, weight: .regular) }
        static var subheadlineSemibold: Font { .system(size: subheadlinePointSize, weight: .semibold) }
        static var callout: Font { .system(size: calloutPointSize, weight: .regular) }
        static var body: Font { .system(size: bodyPointSize, weight: .regular) }
        static var caption: Font { .system(size: captionPointSize, weight: .regular) }
        static var captionSemibold: Font { .system(size: captionPointSize, weight: .semibold) }
        static var caption2: Font { .system(size: caption2PointSize, weight: .regular) }
        static var caption2Semibold: Font { .system(size: caption2PointSize, weight: .semibold) }
        static var footnote: Font { .system(size: footnotePointSize, weight: .regular) }

        private static func scaled(_ baseSize: CGFloat) -> CGFloat {
            baseSize * AppTextSizeOption.currentScaleMultiplier
        }

        private static var title2PointSize: CGFloat { scaled(preferredSize(for: .title2, fallback: 22)) }
        private static var title3PointSize: CGFloat { scaled(preferredSize(for: .title3, fallback: 20)) }
        private static var headlinePointSize: CGFloat { scaled(preferredSize(for: .headline, fallback: 17)) }
        private static var subheadlinePointSize: CGFloat { scaled(preferredSize(for: .subheadline, fallback: 15)) }
        private static var calloutPointSize: CGFloat { scaled(preferredSize(for: .callout, fallback: 16)) }
        private static var bodyPointSize: CGFloat { scaled(preferredSize(for: .body, fallback: 16)) }
        private static var captionPointSize: CGFloat { scaled(preferredSize(for: .caption, fallback: 12)) }
        private static var caption2PointSize: CGFloat { scaled(preferredSize(for: .caption2, fallback: 11)) }
        private static var footnotePointSize: CGFloat { scaled(preferredSize(for: .footnote, fallback: 13)) }

        private static func preferredSize(for textStyle: Font.TextStyle, fallback: CGFloat) -> CGFloat {
#if canImport(UIKit)
            let bodySize = UIFont.preferredFont(forTextStyle: .body).pointSize
            let sizes: [Font.TextStyle: CGFloat] = [
                .title2: UIFont.preferredFont(forTextStyle: .title2).pointSize,
                .title3: UIFont.preferredFont(forTextStyle: .title3).pointSize,
                .headline: UIFont.preferredFont(forTextStyle: .headline).pointSize,
                .subheadline: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                .callout: UIFont.preferredFont(forTextStyle: .callout).pointSize,
                .caption: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                .caption2: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                .footnote: UIFont.preferredFont(forTextStyle: .footnote).pointSize
            ]
            return sizes[textStyle] ?? bodySize
#elseif canImport(AppKit)
            let bodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
            let sizes: [Font.TextStyle: CGFloat] = [
                .title2: NSFont.preferredFont(forTextStyle: .title2).pointSize,
                .title3: NSFont.preferredFont(forTextStyle: .title3).pointSize,
                .headline: NSFont.preferredFont(forTextStyle: .headline).pointSize,
                .subheadline: NSFont.preferredFont(forTextStyle: .subheadline).pointSize,
                .callout: NSFont.preferredFont(forTextStyle: .callout).pointSize,
                .caption: NSFont.preferredFont(forTextStyle: .caption1).pointSize,
                .caption2: NSFont.preferredFont(forTextStyle: .caption2).pointSize,
                .footnote: NSFont.preferredFont(forTextStyle: .footnote).pointSize
            ]
            return sizes[textStyle] ?? bodySize
#else
            return fallback
#endif
        }
    }
}
