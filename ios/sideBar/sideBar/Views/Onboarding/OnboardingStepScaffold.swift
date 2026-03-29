import SwiftUI

private enum OnboardingAutofocus {
    static let delayNanoseconds: UInt64 = 150_000_000
}

enum OnboardingLayoutMode {
    case regular
    case compact

    var topSpacing: CGFloat {
        switch self {
        case .regular:
            DesignTokens.Spacing.xxl
        case .compact:
            DesignTokens.Spacing.lg
        }
    }

    var iconBottomSpacing: CGFloat {
        switch self {
        case .regular:
            DesignTokens.Spacing.md
        case .compact:
            DesignTokens.Spacing.sm
        }
    }

    var titleBottomSpacing: CGFloat {
        DesignTokens.Spacing.xs
    }

    var subtitleBottomSpacing: CGFloat {
        switch self {
        case .regular:
            DesignTokens.Spacing.xl
        case .compact:
            DesignTokens.Spacing.md
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .regular:
            DesignTokens.Spacing.md
        case .compact:
            DesignTokens.Spacing.sm
        }
    }

    var linkSpacing: CGFloat {
        switch self {
        case .regular:
            DesignTokens.Spacing.lg
        case .compact:
            DesignTokens.Spacing.sm
        }
    }

    var horizontalPadding: CGFloat {
        DesignTokens.Spacing.xxl
    }

    var buttonVerticalPadding: CGFloat {
        switch self {
        case .regular:
            DesignTokens.Spacing.md
        case .compact:
            DesignTokens.Spacing.sm
        }
    }

    var footerSpacing: CGFloat {
        switch self {
        case .regular:
            DesignTokens.Spacing.md
        case .compact:
            DesignTokens.Spacing.sm
        }
    }

    var progressTopPadding: CGFloat {
        switch self {
        case .regular:
            DesignTokens.Spacing.lg
        case .compact:
            DesignTokens.Spacing.sm
        }
    }

    var bottomPadding: CGFloat {
        switch self {
        case .regular:
            DesignTokens.Spacing.xl
        case .compact:
            DesignTokens.Spacing.sm
        }
    }
}

/// Shared step scaffold that preserves the normal layout, then falls back to scrolling when height is constrained.
struct OnboardingStepScaffold<Content: View>: View {
    let layoutMode: OnboardingLayoutMode
    let bottomContentInset: CGFloat
    @ViewBuilder private let content: () -> Content

    init(
        layoutMode: OnboardingLayoutMode,
        bottomContentInset: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.layoutMode = layoutMode
        self.bottomContentInset = bottomContentInset
        self.content = content
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(
                    maxWidth: .infinity,
                    minHeight: layoutMode == .compact ? nil : 0,
                    alignment: .top
                )
                .padding(.bottom, bottomContentInset)
        }
        .defaultScrollAnchor(.top)
        .scrollBounceBehavior(.basedOnSize)
#if canImport(UIKit)
        .scrollDismissesKeyboard(.interactively)
#endif
    }
}

extension View {
    func onboardingDeferredAutofocus<Value: Hashable>(
        _ binding: FocusState<Value?>.Binding,
        equals value: Value
    ) -> some View {
        task {
            try? await Task.sleep(nanoseconds: OnboardingAutofocus.delayNanoseconds)
            guard !Task.isCancelled, binding.wrappedValue == nil else { return }
            binding.wrappedValue = value
        }
    }

    func onboardingDeferredAutofocus(_ binding: FocusState<Bool>.Binding) -> some View {
        task {
            try? await Task.sleep(nanoseconds: OnboardingAutofocus.delayNanoseconds)
            guard !Task.isCancelled, binding.wrappedValue == false else { return }
            binding.wrappedValue = true
        }
    }
}
