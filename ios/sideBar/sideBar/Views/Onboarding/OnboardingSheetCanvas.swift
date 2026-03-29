import SwiftUI

enum OnboardingSheetCanvasLayout {
    static let canvasSize = CGSize(width: 420, height: 680)
    static let outerPadding: CGFloat = 24

    static var sheetSize: CGSize {
        CGSize(
            width: canvasSize.width + (outerPadding * 2),
            height: canvasSize.height + (outerPadding * 2)
        )
    }
}

struct OnboardingSheetCanvas<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(
                width: OnboardingSheetCanvasLayout.canvasSize.width,
                height: OnboardingSheetCanvasLayout.canvasSize.height
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(OnboardingSheetCanvasLayout.outerPadding)
#if os(macOS)
            .background(DesignTokens.Colors.background)
            .presentationBackground(DesignTokens.Colors.background)
            .presentationSizing(.fitted)
            .frame(
                minWidth: OnboardingSheetCanvasLayout.sheetSize.width,
                idealWidth: OnboardingSheetCanvasLayout.sheetSize.width,
                minHeight: OnboardingSheetCanvasLayout.sheetSize.height,
                idealHeight: OnboardingSheetCanvasLayout.sheetSize.height
            )
#endif
    }
}
