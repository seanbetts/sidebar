import SwiftUI

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

                Image(systemName: "location.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.iconBottomSpacing)

                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("onboarding.locationPermission.title")
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
                    .padding(.bottom, layoutMode.sectionSpacing)

                if viewModel.isLocationPermissionResolved {
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
