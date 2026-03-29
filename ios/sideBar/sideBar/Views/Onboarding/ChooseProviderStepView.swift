import SwiftUI

/// Step 5 of onboarding for primary provider selection.
struct ChooseProviderStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode

    private struct ProviderOption: Identifiable {
        let provider: AIPrimaryProvider
        let initial: String
        let description: String

        var id: AIPrimaryProvider { provider }
    }

    private let providers: [ProviderOption] = [
        ProviderOption(provider: .anthropic, initial: "A", description: "Claude models"),
        ProviderOption(provider: .openai, initial: "O", description: "GPT models"),
        ProviderOption(provider: .google, initial: "G", description: "Gemini models")
    ]

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: layoutMode.topSpacing)

                Image(systemName: "cpu")
                    .font(.system(size: 48))
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.iconBottomSpacing)

                Text("Pick Your AI Brain")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text("Choose which AI powers me. You can switch anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, layoutMode.subtitleBottomSpacing)

                VStack(spacing: layoutMode.sectionSpacing) {
                    ForEach(providers) { option in
                        providerCard(
                            provider: option.provider,
                            initial: option.initial,
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
        initial: String,
        description: String
    ) -> some View {
        let isSelected = viewModel.selectedProvider == provider
        return Button(action: {
            viewModel.selectedProvider = provider
        }, label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(initial)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(DesignTokens.Colors.muted)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
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
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(DesignTokens.Colors.background)
                            }
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
            }
        })
        .buttonStyle(.plain)
    }
}
