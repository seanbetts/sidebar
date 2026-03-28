import SwiftUI

/// Step 4 of onboarding for optional profile naming.
struct ProfileStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: DesignTokens.Spacing.xxl)

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.primary)
                .padding(.bottom, DesignTokens.Spacing.md)

            Text("What Should I Call You?")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(.primary)
                .padding(.bottom, DesignTokens.Spacing.xs)

            Text("I'll use your name to make our conversations feel more natural.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, DesignTokens.Spacing.xl)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("NAME")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                TextField("Your name", text: $viewModel.displayName)
                    .textContentType(.name)
                    .padding(DesignTokens.Spacing.sm)
                    .background(DesignTokens.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                    .focused($nameFieldFocused)
            }
            .frame(maxWidth: 310)

            Text("You can add pronouns, location, communication preferences, and more in Settings anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
                .padding(.top, DesignTokens.Spacing.sm)

            Spacer()

            VStack(spacing: DesignTokens.Spacing.md) {
                Button(action: {
                    Task { await viewModel.saveProfile() }
                }, label: {
                    Text("Continue")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 310)
                        .padding(.vertical, DesignTokens.Spacing.md)
                })
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Button("Skip for now", action: {
                    viewModel.skipProfile()
                })
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .onAppear {
            nameFieldFocused = true
        }
    }
}
