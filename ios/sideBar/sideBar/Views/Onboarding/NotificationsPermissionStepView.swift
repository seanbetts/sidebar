import SwiftUI
import sideBarShared

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

                Image(appIcon: AppIcon.Onboarding.notificationsPermission)
                    .appFont(.displayLg)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.iconBottomSpacing)

                Text(title)
                    .appFont(.displayMd)
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("onboarding.notificationsPermission.title")
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text(subtitle)
                    .appFont(.body)
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
