import SwiftUI

struct MacPopoverShell<Content: View>: View {
    let type: MacPanelType
    let content: Content

    init(type: MacPanelType = .compactPopover, @ViewBuilder content: () -> Content) {
        self.type = type
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
