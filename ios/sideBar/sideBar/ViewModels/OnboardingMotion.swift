import SwiftUI

enum OnboardingMotion {
    static func animation(for direction: OnboardingNavigationDirection) -> Animation {
        switch direction {
        case .forward, .backward:
            return .smooth(duration: 0.24)
        }
    }
}
