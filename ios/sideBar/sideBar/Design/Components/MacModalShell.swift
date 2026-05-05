import SwiftUI

#if os(macOS)
struct MacModalShell<Content: View>: View {
    let type: MacPanelType
    let content: Content

    init(type: MacPanelType, @ViewBuilder content: () -> Content) {
        self.type = type
        self.content = content()
    }

    var body: some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .glassChrome(Self.chromeKind)
            .presentationBackground(.clear)
            .presentationSizing(.fitted)
            .frame(
                minWidth: minWidth,
                idealWidth: idealWidth,
                maxWidth: maxWidth
            )
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
        .modalShell
    }

    static func minimumWidth(for type: MacPanelType) -> CGFloat {
        macModalFrameWidth(for: type)
    }

    static func maximumWidth(for type: MacPanelType) -> CGFloat {
        type == .largeInspectorSheet ? DesignTokens.Size.inspectorMaxWidth : minimumWidth(for: type) + 80
    }
}
#else
struct MacModalShell<Content: View>: View {
    let type: MacPanelType
    let content: Content

    init(type: MacPanelType, @ViewBuilder content: () -> Content) {
        self.type = type
        self.content = content()
    }

    var body: some View {
        content
    }

    static var chromeKind: GlassChrome.Kind {
        .modalShell
    }

    static func minimumWidth(for type: MacPanelType) -> CGFloat {
        macModalFrameWidth(for: type)
    }

    static func maximumWidth(for type: MacPanelType) -> CGFloat {
        type == .largeInspectorSheet ? DesignTokens.Size.inspectorMaxWidth : minimumWidth(for: type) + 80
    }
}
#endif
