import SwiftUI

enum MacPopoverPresentationBackground {
    case clear
    case appBackground
}

struct MacPopoverShell<Content: View>: View {
    let type: MacPanelType
    let presentationBackground: MacPopoverPresentationBackground
    let content: Content

    init(
        type: MacPanelType = .compactPopover,
        presentationBackground: MacPopoverPresentationBackground = .clear,
        @ViewBuilder content: () -> Content
    ) {
        self.type = type
        self.presentationBackground = presentationBackground
        self.content = content()
    }

    var body: some View {
        content
            .padding(Self.contentPadding)
            .frame(
                minWidth: minWidth,
                idealWidth: idealWidth,
                maxWidth: maxWidth,
                alignment: .topLeading
            )
            .glassChrome(Self.chromeKind)
            .modifier(PresentationBackgroundModifier(background: presentationBackground))
    }

    private var minWidth: CGFloat {
        Self.minimumWidth(for: type)
    }

    private var idealWidth: CGFloat {
        minWidth
    }

    private var maxWidth: CGFloat {
        Self.maximumWidth(for: type)
    }

    static var chromeKind: GlassChrome.Kind {
        .popoverShell
    }

    static var contentPadding: CGFloat {
        DesignTokens.Spacing.md
    }

    static func minimumWidth(for type: MacPanelType) -> CGFloat {
        switch type {
        case .compactPopover:
            return 280
        case .compactSheet, .decisionSheet:
            return 320
        case .chooserSheet:
            return 360
        case .editorSheet:
            return 420
        case .largeInspectorSheet:
            return 520
        }
    }

    static func maximumWidth(for type: MacPanelType) -> CGFloat {
        max(minimumWidth(for: type), macModalFrameWidth(for: type))
    }
}

private struct PresentationBackgroundModifier: ViewModifier {
    let background: MacPopoverPresentationBackground

    func body(content: Content) -> some View {
        switch background {
        case .clear:
            content.presentationBackground(.clear)
        case .appBackground:
            content.presentationBackground(DesignTokens.Colors.background)
        }
    }
}
