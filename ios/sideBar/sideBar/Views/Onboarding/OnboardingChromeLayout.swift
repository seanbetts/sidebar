import SwiftUI

enum OnboardingBottomChromePlacement: Equatable {
    case overlay
}

enum OnboardingChromeLayoutPolicy {
    static let bottomAreaPlacement: OnboardingBottomChromePlacement = .overlay
    static let rootIgnoresKeyboardSafeArea = true

    static func contentBottomInset(
        for bottomAreaHeight: CGFloat,
        keyboardHeight: CGFloat = 0
    ) -> CGFloat {
        max(0, bottomAreaHeight + keyboardHeight)
    }
}

private struct OnboardingBottomAreaHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func onboardingBottomAreaHeightReader() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: OnboardingBottomAreaHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
            }
        }
    }

    func onOnboardingBottomAreaHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        onPreferenceChange(OnboardingBottomAreaHeightPreferenceKey.self, perform: action)
    }
}
