import SwiftUI

/// Step 8 of onboarding for explicit notifications permission handling.
struct NotificationsPermissionStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let bottomContentInset: CGFloat

    private var title: String {
        guard viewModel.isNotificationsPermissionResolved else { return "Stay In The Loop" }
        switch viewModel.notificationsPermissionState {
        case .granted:
            return "Notifications Enabled"
        case .notAsked, .denied:
            return "Notifications Skipped"
        }
    }

    private var subtitle: String {
        guard viewModel.isNotificationsPermissionResolved else {
            return "Enable notifications for due tasks, finished processing, and assistant follow-up."
        }

        switch viewModel.notificationsPermissionState {
        case .granted:
            return "You'll be able to get alerts for due tasks, finished processing, and assistant follow-up."
        case .notAsked, .denied:
            return "You can keep going without notifications. You can change this later in Settings."
        }
    }

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode, bottomContentInset: bottomContentInset) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: layoutMode.topSpacing)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.iconBottomSpacing)

                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("onboarding.notificationsPermission.title")
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
                    .padding(.bottom, layoutMode.sectionSpacing)

                if viewModel.isNotificationsPermissionResolved {
                    Text("You can revisit this in Settings at any time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 310)
                }

                Spacer()
            }
            .padding(.horizontal, layoutMode.horizontalPadding)
        }
    }
}
