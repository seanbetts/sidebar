import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum HeaderActionControlMetrics {
    static let symbolPointSize: CGFloat = DesignTokens.Icon.sm
    static let iconFrameWidth: CGFloat = 28
    static let iconFrameHeight: CGFloat = 20
    static let chromePadding: CGFloat = DesignTokens.Spacing.xxsPlus
    static let rowSpacing: CGFloat = DesignTokens.Spacing.xs
    static let chromeWidth: CGFloat = iconFrameWidth + (chromePadding * 2)
    static let chromeHeight: CGFloat = iconFrameHeight + (chromePadding * 2)
}

enum HeaderActionControlChromeStyle: Equatable {
    case plain
    case glass

    var kind: GlassChrome.Kind {
        .actionButton
    }

    var appliesChrome: Bool {
        switch self {
        case .plain:
            return false
        case .glass:
            return true
        }
    }
}

struct HeaderActionIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .appFont(.labelMd)
            .frame(
                width: HeaderActionControlMetrics.iconFrameWidth,
                height: HeaderActionControlMetrics.iconFrameHeight
            )
            .imageScale(.medium)
    }
}

struct HeaderActionButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
    var isDisabled: Bool = false
    var chromeStyle: HeaderActionControlChromeStyle = .plain

    var body: some View {
        Button(action: action) {
            HeaderActionIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .headerActionControlChrome(chromeStyle)
        .accessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
    }
}

struct HeaderActionMenuControl<MenuContent: View>: View {
    let systemName: String
    let accessibilityLabel: String
    var chromeStyle: HeaderActionControlChromeStyle = .plain
    let menuContent: MenuContent

    init(
        systemName: String,
        accessibilityLabel: String,
        chromeStyle: HeaderActionControlChromeStyle = .plain,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.chromeStyle = chromeStyle
        self.menuContent = menuContent()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            HeaderActionIcon(systemName: systemName)
                .headerActionControlChrome(chromeStyle)
        }
        .buttonStyle(.plain)
#if os(macOS)
        .menuIndicator(.hidden)
#endif
        .accessibilityLabel(accessibilityLabel)
    }
}

struct HeaderActionRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(
        spacing: CGFloat = HeaderActionControlMetrics.rowSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}

enum HeaderActionControlChromeBridge {
#if os(iOS)
    static func borderColor(
        for style: HeaderActionControlChromeStyle,
        traitCollection: UITraitCollection
    ) -> UIColor {
        switch style {
        case .plain:
            return .clear
        case .glass:
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor.white.withAlphaComponent(0.22)
            default:
                return UIColor.black.withAlphaComponent(0.12)
            }
        }
    }
#elseif os(macOS)
    static func borderColor(
        for style: HeaderActionControlChromeStyle,
        appearance: NSAppearance
    ) -> NSColor {
        switch style {
        case .plain:
            return .clear
        case .glass:
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor.white.withAlphaComponent(0.22)
            default:
                return NSColor.black.withAlphaComponent(0.12)
            }
        }
    }
#endif
}

#if os(iOS)
struct HeaderActionMenuButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let items: [SidebarMenuItem]
    let isCompact: Bool
    var chromeStyle: HeaderActionControlChromeStyle = .plain

    var body: some View {
        let menuSignature = items
            .map { "\($0.title)|\($0.systemImage ?? "")|\(roleSignature($0.role))" }
            .joined(separator: ";")
        HeaderActionMenuControl(
            systemName: systemImage,
            accessibilityLabel: accessibilityLabel,
            chromeStyle: chromeStyle
        ) {
            sidebarMenuItemsView(items)
        }
        .id(menuSignature)
    }

    private func roleSignature(_ role: ButtonRole?) -> String {
        switch role {
        case .destructive:
            return "destructive"
        case .cancel:
            return "cancel"
        default:
            return "default"
        }
    }
}
#endif

private struct HeaderActionControlChromeModifier: ViewModifier {
    let style: HeaderActionControlChromeStyle

    func body(content: Content) -> some View {
        if style.appliesChrome {
            content
                .padding(HeaderActionControlMetrics.chromePadding)
                .glassChrome(style.kind)
        } else {
            content
        }
    }
}

extension View {
    func headerActionControlChrome(_ style: HeaderActionControlChromeStyle) -> some View {
        modifier(HeaderActionControlChromeModifier(style: style))
    }
}
