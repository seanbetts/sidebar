import SwiftUI

enum OnboardingStepTransitionStyle: Equatable {
    case movingForward
    case movingBackward
    case reducedMotion
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

    var body: some View {
        let style = Self.transitionStyle(
            reduceMotion: accessibilityReduceMotion,
            direction: direction
        )

        return ZStack {
            content()
                .id(step)
                .transition(Self.transition(for: style))
        }
        .animation(Self.animation(for: style), value: step)
    }

    private static func animation(for style: OnboardingStepTransitionStyle) -> Animation {
        switch style {
        case .reducedMotion:
            return .easeOut(duration: 0.12)
        case .movingForward, .movingBackward:
            return .smooth(duration: 0.24)
        }
    }

    private static func transition(for style: OnboardingStepTransitionStyle) -> AnyTransition {
        switch style {
        case .movingForward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .movingBackward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .reducedMotion:
            return .opacity
        }
    }
}
