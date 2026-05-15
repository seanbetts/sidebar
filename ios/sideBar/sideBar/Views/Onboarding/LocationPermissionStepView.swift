import SwiftUI
import sideBarShared

/// Step 7 of onboarding for explicit location permission handling.
struct LocationPermissionStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let bottomContentInset: CGFloat

    private var title: String {
        guard viewModel.isLocationPermissionResolved else { return "Share Your Location" }
        switch viewModel.locationPermissionState {
        case .granted:
            return "Location Enabled"
        case .notAsked, .denied:
            return "Location Skipped"
        }
    }

    private var subtitle: String {
        guard viewModel.isLocationPermissionResolved else {
            return "Enable location for weather, local recommendations, and time-aware responses."
        }

        switch viewModel.locationPermissionState {
        case .granted:
            return "You're set up for weather, local recommendations, and time-aware responses."
        case .notAsked, .denied:
            return "You can keep going without location. You can change this later in Settings."
        }
    }

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode, bottomContentInset: bottomContentInset) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: layoutMode.topSpacing)

                Image(appIcon: AppIcon.Onboarding.locationPermission)
                    .appFont(.displayLg)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.iconBottomSpacing)

                Text(title)
                    .appFont(.displayMd)
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("onboarding.locationPermission.title")
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
