import SwiftUI

enum OnboardingStepTransitionStyle: Equatable {
    case movingForward
    case movingBackward
    case reducedMotion
}

enum OnboardingStepTransitionRecipe: Equatable {
    case slideForward
    case slideBackward
    case reducedMotion
}

enum OnboardingStepTransitionViewportPolicy {
    static let clipsAnimatedContent = true
}

/// Content-only transition wrapper for onboarding step changes.
struct OnboardingStepTransitionContainer<Content: View>: View {
    let step: OnboardingStep
    let direction: OnboardingNavigationDirection
    @ViewBuilder private let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(
        step: OnboardingStep,
        direction: OnboardingNavigationDirection,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.step = step
        self.direction = direction
        self.content = content
    }

    static func transitionStyle(
        reduceMotion: Bool,
        direction: OnboardingNavigationDirection
    ) -> OnboardingStepTransitionStyle {
        guard !reduceMotion else { return .reducedMotion }
        switch direction {
        case .forward:
            return .movingForward
        case .backward:
            return .movingBackward
        }
    }

    static func transitionRecipe(
        reduceMotion: Bool,
        direction: OnboardingNavigationDirection
    ) -> OnboardingStepTransitionRecipe {
        guard !reduceMotion else { return .reducedMotion }
        switch direction {
        case .forward:
            return .slideForward
        case .backward:
            return .slideBackward
        }
    }

    var body: some View {
        let recipe = Self.transitionRecipe(
            reduceMotion: accessibilityReduceMotion,
            direction: direction
        )

        return ZStack {
            content()
                .id(step)
                .transition(Self.transition(for: recipe))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(OnboardingStepClipModifier())
    }

    private static func transition(for recipe: OnboardingStepTransitionRecipe) -> AnyTransition {
        switch recipe {
        case .slideForward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .slideBackward:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        case .reducedMotion:
            return .opacity
        }
    }
}

private struct OnboardingStepClipModifier: ViewModifier {
    func body(content: Content) -> some View {
        if OnboardingStepTransitionViewportPolicy.clipsAnimatedContent {
            content.clipped()
        } else {
            content
        }
    }
}
