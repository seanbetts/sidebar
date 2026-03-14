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
            .padding(DesignTokens.Spacing.md)
            .frame(
                minWidth: minWidth,
                idealWidth: idealWidth,
                maxWidth: maxWidth,
                alignment: .topLeading
            )
            .background(DesignTokens.Colors.surface)
    }

    private var minWidth: CGFloat {
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

    private var idealWidth: CGFloat {
        minWidth
    }

    private var maxWidth: CGFloat {
        max(minWidth, macModalFrameWidth(for: type))
    }
}
