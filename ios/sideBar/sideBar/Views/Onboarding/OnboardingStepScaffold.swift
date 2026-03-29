import SwiftUI

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
    @ViewBuilder private let content: () -> Content

    init(
        layoutMode: OnboardingLayoutMode,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.layoutMode = layoutMode
        self.content = content
    }

    var body: some View {
        Group {
            if layoutMode == .compact {
                compactScrollableContent
            } else {
                regularContent
            }
        }
    }

    private var regularContent: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var compactScrollableContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, layoutMode.bottomPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
#if canImport(UIKit)
        .scrollDismissesKeyboard(.interactively)
#endif
    }
}
