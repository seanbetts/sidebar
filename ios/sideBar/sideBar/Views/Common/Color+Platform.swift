import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private struct AppRGBA {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    func opacity(_ alpha: Double) -> AppRGBA {
        AppRGBA(red, green, blue, alpha: alpha)
    }

    static let white = AppRGBA(1, 1, 1)
    static let hex0A0A0A = AppRGBA(0.039, 0.039, 0.039)
    static let hex171717 = AppRGBA(0.090, 0.090, 0.090)
    static let hex262626 = AppRGBA(0.149, 0.149, 0.149)
    static let hexFAFAFA = AppRGBA(0.980, 0.980, 0.980)
    static let hexF5F5F5 = AppRGBA(0.961, 0.961, 0.961)
    static let hexE5E5E5 = AppRGBA(0.898, 0.898, 0.898)
}

private struct AppDynamicColor {
    let name: String
    let light: AppRGBA
    let dark: AppRGBA

    var color: Color {
        #if os(macOS)
        return Color(nsColor: nsColor)
        #else
        return Color(uiColor: uiColor)
        #endif
    }
}

private enum AppPalette {
    static let background = AppDynamicColor(name: "appBackground", light: .white, dark: .hex0A0A0A)
    static let surface = AppDynamicColor(name: "appSurface", light: .white, dark: .hex171717)
    static let muted = AppDynamicColor(name: "appMuted", light: .hexF5F5F5, dark: .hex262626)
    static let sidebar = AppDynamicColor(name: "appSidebar", light: .hexFAFAFA, dark: .hex171717)
    static let sidebarAccent = AppDynamicColor(name: "appSidebarAccent", light: .hexF5F5F5, dark: .hex262626)
    static let border = AppDynamicColor(name: "appBorder", light: .hexE5E5E5, dark: .white.opacity(0.10))
    static let input = AppDynamicColor(name: "appInput", light: .hexE5E5E5, dark: .white.opacity(0.15))
}

#if os(macOS)
private extension AppRGBA {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension AppDynamicColor {
    var nsColor: NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark.nsColor : light.nsColor
        }
    }
}

extension NSColor {
    static var appBackground: NSColor {
        AppPalette.background.nsColor
    }
}
#else
private extension AppRGBA {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension AppDynamicColor {
    var uiColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
        }
    }
}
#endif

extension Color {
    static var platformSystemBackground: Color {
        AppPalette.background.color
    }

    static var platformSecondarySystemBackground: Color {
        AppPalette.muted.color
    }

    static var platformSeparator: Color {
        AppPalette.border.color
    }

    static var platformTertiaryLabel: Color {
        #if os(macOS)
        return Color(nsColor: .tertiaryLabelColor)
        #else
        return Color(uiColor: .tertiaryLabel)
        #endif
    }

    static var platformSystemGray6: Color {
        AppPalette.muted.color
    }

    static var platformUnderPageBackground: Color {
        AppPalette.sidebar.color
    }

    static var appBackground: Color {
        AppPalette.background.color
    }

    static var appSurface: Color {
        AppPalette.surface.color
    }

    static var appMuted: Color {
        AppPalette.muted.color
    }

    static var appSidebar: Color {
        AppPalette.sidebar.color
    }

    static var appSidebarAccent: Color {
        AppPalette.sidebarAccent.color
    }

    static var appBorder: Color {
        AppPalette.border.color
    }

    static var appInput: Color {
        AppPalette.input.color
    }

    static var appSelection: Color {
        Color.accentColor.opacity(0.18)
    }

    /// Outer chrome/wrapper background for settings panels.
    static var appSettingsBackground: Color {
        AppPalette.background.color
    }

    /// Inner form/list background for settings panels.
    static var appSettingsFormBackground: Color {
        AppPalette.surface.color
    }
}
