import SwiftUI

/// Step 8 of onboarding for explicit notifications permission handling.
struct NotificationsPermissionStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let bottomContentInset: CGFloat

    private var title: String {
        if viewModel.isRefreshingNotificationsPermissionState {
            return "Checking Notification Status"
        }
        if viewModel.isNotificationsPermissionResolved && viewModel.notificationsPermissionState == .granted {
            return "Notifications Enabled"
        }
        return "Stay In The Loop"
    }

    private var subtitle: String {
        if viewModel.isRefreshingNotificationsPermissionState {
            return "Checking whether notifications are already enabled for this device."
        }
        if viewModel.isNotificationsPermissionResolved && viewModel.notificationsPermissionState == .granted {
            return "You'll be able to get alerts for due tasks, finished processing, and assistant follow-up."
        }
        return "Enable notifications for due tasks, finished processing, and assistant follow-up."
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

                Spacer()
            }
            .padding(.horizontal, layoutMode.horizontalPadding)
        }
    }
}
