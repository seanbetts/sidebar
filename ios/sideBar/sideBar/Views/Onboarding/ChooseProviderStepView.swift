import SwiftUI

/// Step 5 of onboarding for primary provider selection.
struct ChooseProviderStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let bottomContentInset: CGFloat

    private struct ProviderOption: Identifiable {
        let provider: AIPrimaryProvider
        let description: String

        var id: AIPrimaryProvider { provider }
    }

    private let providers: [ProviderOption] = [
        ProviderOption(provider: .anthropic, description: "Claude models"),
        ProviderOption(provider: .openai, description: "GPT models"),
        ProviderOption(provider: .google, description: "Gemini models")
    ]

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode, bottomContentInset: bottomContentInset) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: layoutMode.topSpacing)

                Image(systemName: "brain")
                    .appFont(.displayLg)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.iconBottomSpacing)

                Text("Pick Your AI Brain")
                    .appFont(.displayMd)
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text("Choose which AI powers me. You can switch anytime in Settings.")
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, layoutMode.subtitleBottomSpacing)

                VStack(spacing: layoutMode.sectionSpacing) {
                    ForEach(providers) { option in
                        providerCard(
                            provider: option.provider,
                            description: option.description
                        )
                    }
                }
                .frame(maxWidth: 310)

                Spacer()
            }
            .padding(.horizontal, layoutMode.horizontalPadding)
        }
    }

    private func providerCard(
        provider: AIPrimaryProvider,
        description: String
    ) -> some View {
        let isSelected = viewModel.selectedProvider == provider
        return Button(action: {
            viewModel.selectProvider(provider)
        }, label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                OnboardingProviderLogoBadge(
                    provider: provider,
                    logoSize: 26,
                    containerSize: 40
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .appFont(.body)
                        .foregroundStyle(.primary)
                    Text(description)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.clear : DesignTokens.Colors.muted, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .appFont(.badge)
                                    .foregroundStyle(DesignTokens.Colors.background)
                            }
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.Colors.muted)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
            }
        })
        .buttonStyle(.plain)
    }
}
