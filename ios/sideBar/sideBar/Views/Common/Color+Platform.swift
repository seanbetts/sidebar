import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
private enum MacOSPalette {
    static let background = makeDynamicNSColor(
        name: "macosBackground",
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.039, green: 0.039, blue: 0.039, alpha: 1)
    )
    static let card = makeDynamicNSColor(
        name: "macosCard",
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.090, green: 0.090, blue: 0.090, alpha: 1)
    )
    static let muted = makeDynamicNSColor(
        name: "macosMuted",
        light: NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1),
        dark: NSColor(srgbRed: 0.149, green: 0.149, blue: 0.149, alpha: 1)
    )
    static let sidebar = makeDynamicNSColor(
        name: "macosSidebar",
        light: NSColor(srgbRed: 0.980, green: 0.980, blue: 0.980, alpha: 1),
        dark: NSColor(srgbRed: 0.090, green: 0.090, blue: 0.090, alpha: 1)
    )
    static let sidebarAccent = makeDynamicNSColor(
        name: "macosSidebarAccent",
        light: NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1),
        dark: NSColor(srgbRed: 0.149, green: 0.149, blue: 0.149, alpha: 1)
    )
    static let border = makeDynamicNSColor(
        name: "macosBorder",
        light: NSColor(srgbRed: 0.898, green: 0.898, blue: 0.898, alpha: 1),
        dark: NSColor(white: 1, alpha: 0.1)
    )
    static let input = makeDynamicNSColor(
        name: "macosInput",
        light: NSColor(srgbRed: 0.898, green: 0.898, blue: 0.898, alpha: 1),
        dark: NSColor(white: 1, alpha: 0.15)
    )
}

private func makeDynamicNSColor(name: String, light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: NSColor.Name(name)) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? dark : light
    }
}

extension NSColor {
    static var appBackground: NSColor {
        MacOSPalette.background
    }
}
#endif

extension Color {
    static var platformSystemBackground: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.background)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    static var platformSecondarySystemBackground: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.muted)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var platformSeparator: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.border)
        #else
        return Color(uiColor: .separator)
        #endif
    }

    static var platformTertiaryLabel: Color {
        #if os(macOS)
        return Color(nsColor: .tertiaryLabelColor)
        #else
        return Color(uiColor: .tertiaryLabel)
        #endif
    }

    static var platformSystemGray6: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.muted)
        #else
        return Color(uiColor: .systemGray6)
        #endif
    }

    static var platformUnderPageBackground: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.sidebar)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var appBackground: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.background)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    static var appSurface: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.card)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var appMuted: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.muted)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var appSidebar: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.sidebar)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var appSidebarAccent: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.sidebarAccent)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    static var appBorder: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.border)
        #else
        return Color(uiColor: .separator)
        #endif
    }

    static var appInput: Color {
        #if os(macOS)
        return Color(nsColor: MacOSPalette.input)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    static var appSelection: Color {
        Color.accentColor.opacity(0.18)
    }
}
