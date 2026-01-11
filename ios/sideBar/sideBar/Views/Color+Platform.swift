import SwiftUI

extension Color {
    static var platformSystemBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    static var platformSecondarySystemBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var platformSeparator: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
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
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .systemGray6)
        #endif
    }

    static var platformUnderPageBackground: Color {
        #if os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
