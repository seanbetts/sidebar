import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum HeaderActionControlMetrics {
    private static let baseIconFrameWidth: CGFloat = 28
    private static let baseIconFrameHeight: CGFloat = 20
    private static let baseChromePadding: CGFloat = DesignTokens.Spacing.xxsPlus

    static func symbolPointSize(for option: AppTextSizeOption) -> CGFloat {
        AppFontStyle.label.pointSize(for: option)
    }

    static func iconFrameWidth(for option: AppTextSizeOption) -> CGFloat {
        AppFontStyle.scaledMetric(baseIconFrameWidth, for: option)
    }

    static func iconFrameHeight(for option: AppTextSizeOption) -> CGFloat {
        AppFontStyle.scaledMetric(baseIconFrameHeight, for: option)
    }

    static func chromePadding(for option: AppTextSizeOption) -> CGFloat {
        AppFontStyle.scaledMetric(baseChromePadding, for: option)
    }

    static let rowSpacing: CGFloat = DesignTokens.Spacing.xs

    static func chromeWidth(for option: AppTextSizeOption) -> CGFloat {
        iconFrameWidth(for: option) + (chromePadding(for: option) * 2)
    }

    static func chromeHeight(for option: AppTextSizeOption) -> CGFloat {
        iconFrameHeight(for: option) + (chromePadding(for: option) * 2)
    }

    static var symbolPointSize: CGFloat { symbolPointSize(for: .current) }
    static var iconFrameWidth: CGFloat { iconFrameWidth(for: .current) }
    static var iconFrameHeight: CGFloat { iconFrameHeight(for: .current) }
    static var chromePadding: CGFloat { chromePadding(for: .current) }
    static var chromeWidth: CGFloat { chromeWidth(for: .current) }
    static var chromeHeight: CGFloat { chromeHeight(for: .current) }
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
            .appFont(.label)
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
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HeaderActionIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .headerActionControlChrome(chromeStyle, isHovered: isHovered)
        .accessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
        .sidebarHover($isHovered)
    }
}

struct HeaderActionMenuControl<MenuContent: View>: View {
    let systemName: String
    let accessibilityLabel: String
    var chromeStyle: HeaderActionControlChromeStyle = .plain
    let menuContent: MenuContent
    @State private var isHovered = false

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
                .headerActionControlChrome(chromeStyle, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .iOSMenuPresentationIsolation()
#if os(macOS)
        .menuIndicator(.hidden)
#endif
        .accessibilityLabel(accessibilityLabel)
        .sidebarHover($isHovered)
    }
}

private extension View {
    @ViewBuilder
    func iOSMenuPresentationIsolation() -> some View {
#if os(iOS)
        compositingGroup()
#else
        self
#endif
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
    let isHovered: Bool

    func body(content: Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(isHovered ? DesignTokens.Colors.sidebarHoverBackground : .clear)

            if style.appliesChrome {
                Color.clear
                    .glassChrome(style.kind)
                    .opacity(isHovered ? 0.96 : 1)
            }

            content
        }
        .frame(
            width: HeaderActionControlMetrics.chromeWidth,
            height: HeaderActionControlMetrics.chromeHeight
        )
    }
}

extension View {
    func headerActionControlChrome(
        _ style: HeaderActionControlChromeStyle,
        isHovered: Bool = false
    ) -> some View {
        modifier(HeaderActionControlChromeModifier(style: style, isHovered: isHovered))
    }
}
