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
            .background(backgroundColor)
            .presentationBackground(backgroundColor)
            .presentationSizing(.fitted)
            .frame(
                minWidth: macModalFrameWidth(for: type),
                idealWidth: macModalFrameWidth(for: type),
                maxWidth: type == .largeInspectorSheet ? 1_120 : macModalFrameWidth(for: type) + 80
            )
    }

    private var backgroundColor: Color {
        type == .largeInspectorSheet ? DesignTokens.Colors.settingsBackground : DesignTokens.Colors.background
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
}
#endif
