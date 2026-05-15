import SwiftUI
import sideBarShared

/// Step 6 of onboarding for BYOK setup.
struct AddApiKeyStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let bottomContentInset: CGFloat
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode, bottomContentInset: bottomContentInset) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: layoutMode.topSpacing)

                if let provider = viewModel.selectedProvider {
                    OnboardingProviderLogoBadge(
                        provider: provider,
                        logoSize: 40,
                        containerSize: 64
                    )
                        .padding(.bottom, layoutMode.iconBottomSpacing)
                } else {
                    Image(appIcon: AppIcon.Settings.credentials)
                        .appFont(.displayLg)
                        .foregroundStyle(.primary)
                        .padding(.bottom, layoutMode.iconBottomSpacing)
                }

                Text("Connect Me")
                    .appFont(.displayMd)
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text(viewModel.addApiKeySubtitle)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, layoutMode.linkSpacing)

                if let url = viewModel.providerHelpURL {
                    Link(destination: url, label: {
                        HStack(spacing: 4) {
                            Text("Where do I find this?")
                            Image(appIcon: AppIcon.Onboarding.externalHelp)
                                .appFont(.caption)
                        }
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                        .underline()
                    })
                    .padding(.bottom, layoutMode.linkSpacing)
                }

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("API KEY")
                        .appFont(.label)
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    SecureField(viewModel.apiKeyPlaceholder, text: $viewModel.apiKey)
                        .textContentType(.password)
#if canImport(UIKit)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled()
                        .padding(DesignTokens.Spacing.sm)
                        .background(DesignTokens.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                        .focused($keyFieldFocused)
                        .submitLabel(.continue)
                        .onSubmit {
                            guard !viewModel.trimmedApiKey.isEmpty && !viewModel.isLoading else { return }
                            Task { await viewModel.validateAndSaveApiKey() }
                        }
                }
                .frame(maxWidth: 310)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                        .padding(.top, layoutMode.sectionSpacing)
                }

                let providerName = viewModel.selectedProvider?.displayName ?? "your provider"
                Text(
                    "I use your own API key to talk to \(providerName). " +
                    "Your key is encrypted and never shared."
                )
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
                    .padding(.top, layoutMode.sectionSpacing)

                Spacer()
            }
            .padding(.horizontal, layoutMode.horizontalPadding)
        }
        .onboardingDeferredAutofocus($keyFieldFocused)
    }
}
