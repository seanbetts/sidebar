import SwiftUI
import sideBarShared

/// Step 4 of onboarding for optional profile naming.
struct ProfileStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let bottomContentInset: CGFloat
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode, bottomContentInset: bottomContentInset) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: layoutMode.topSpacing)

                Image(appIcon: AppIcon.Settings.profileAdd)
                    .appFont(.displayLg)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.iconBottomSpacing)

                Text("What Should I Call You?")
                    .appFont(.displayMd)
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text("I'll use your name to make our conversations feel more natural.")
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, layoutMode.subtitleBottomSpacing)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("NAME")
                        .appFont(.label)
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    TextField("Your name", text: $viewModel.displayName)
                        .textContentType(.name)
                        .padding(DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                        .focused($nameFieldFocused)
                        .submitLabel(.continue)
                        .onSubmit {
                            Task { await viewModel.saveProfile() }
                        }
                }
                .frame(maxWidth: 310)

                Text("You can add pronouns, location, communication preferences, and more in Settings anytime.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
                    .padding(.top, layoutMode.sectionSpacing)

                Spacer()
            }
            .padding(.horizontal, layoutMode.horizontalPadding)
        }
        .onboardingDeferredAutofocus($nameFieldFocused)
    }
}
