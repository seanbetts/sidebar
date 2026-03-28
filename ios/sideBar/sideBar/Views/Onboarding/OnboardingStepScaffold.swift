import SwiftUI

/// Shared step scaffold that preserves the normal layout, then falls back to scrolling when height is constrained.
struct OnboardingStepScaffold<Content: View>: View {
    @ViewBuilder private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            ViewThatFits(in: .vertical) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                ScrollView(.vertical, showsIndicators: false) {
                    content()
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
#if canImport(UIKit)
                .scrollDismissesKeyboard(.interactively)
#endif
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}
