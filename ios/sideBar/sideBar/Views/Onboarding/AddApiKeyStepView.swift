import SwiftUI

/// Step 6 of onboarding for BYOK setup.
struct AddApiKeyStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        OnboardingStepScaffold {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: DesignTokens.Spacing.xxl)

                Image(systemName: "key.horizontal")
                    .font(.system(size: 48))
                    .foregroundStyle(.primary)
                    .padding(.bottom, DesignTokens.Spacing.md)

                Text("Connect Me")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, DesignTokens.Spacing.xs)

                Text(viewModel.addApiKeySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, DesignTokens.Spacing.lg)

                if let url = viewModel.providerHelpURL {
                    Link(destination: url, label: {
                        HStack(spacing: 4) {
                            Text("Where do I find this?")
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .underline()
                    })
                    .padding(.bottom, DesignTokens.Spacing.lg)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("API KEY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    SecureField(viewModel.apiKeyPlaceholder, text: $viewModel.apiKey)
                        .textContentType(.password)
#if canImport(UIKit)
                        .textInputAutocapitalization(.never)
#endif
                .frame(maxWidth: 310)
                        .autocorrectionDisabled()
                        .padding(DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                        .focused($keyFieldFocused)
                }
                .frame(maxWidth: 310)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                        .padding(.top, DesignTokens.Spacing.sm)
                }

                let providerName = viewModel.selectedProvider?.displayName ?? "your provider"
                Text(
                    "I use your own API key to talk to \(providerName). " +
                    "Your key is encrypted and never shared."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
                    .padding(.top, DesignTokens.Spacing.sm)

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
        }
        .onAppear {
            keyFieldFocused = true
        }
    }
}
