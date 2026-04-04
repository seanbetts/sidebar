import SwiftUI

extension SoulCalibrationPromptView {
    var introContent: some View {
        SoulCalibrationFooter {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Spacer()

                ContinueButton(
                    title: "Continue",
                    isEnabled: !isBusy,
                    action: onContinueIntro
                )
            }
        }
    }

    var nameConfirmationContent: some View {
        if !isShowingResolvedName {
            return AnyView(nameLoadingContent)
        }

        return AnyView(nameResolvedContent)
    }

    var nameLoadingContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            SoulCalibrationNameBadge {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    LoadingIndicatorView(size: LoadingIndicatorSize.panel)

                    Text("Choosing a name for myself...")
                        .appFont(.body)
                        .foregroundColor(.black.opacity(0.72))
                }
                .frame(maxWidth: .infinity)
            }

            SoulCalibrationFooter {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    standardBackButton

                    Spacer()

                    if let errorMessage, !errorMessage.isEmpty {
                        ContinueButton(
                            title: "Retry",
                            isEnabled: !isBusy,
                            action: onRegenerateName
                        )
                    }
                }
            }
        }
    }

    var nameResolvedContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            SoulCalibrationNameBadge {
                VStack(spacing: DesignTokens.Spacing.xxxs) {
                    if let proposedName = state.proposedName {
                        Text(proposedName)
                            .appScaledFont(size: 58, weight: .bold)
                            .foregroundColor(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .allowsTightening(true)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    Text("This feels like me.")
                        .appFont(.body)
                        .foregroundColor(.black.opacity(0.64))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            SoulCalibrationFooter {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    standardBackButton

                    Spacer()

                    ContinueButton(
                        title: "Try another",
                        isEnabled: !isBusy,
                        action: onRegenerateName,
                        style: .secondary
                    )

                    ContinueButton(
                        title: "Hello!",
                        isEnabled: !isBusy,
                        action: onAcceptName
                    )
                }
            }
        }
    }

    func continueButton(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        SoulCalibrationFooter {
            HStack(spacing: DesignTokens.Spacing.sm) {
                standardBackButton

                Spacer()

                if showsFooterLoadingIndicator {
                    SoulCalibrationFooterProgressIndicator()
                }

                ContinueButton(
                    title: "Continue",
                    isEnabled: isEnabled && !isBusy,
                    action: action
                )
            }
        }
    }

    var showsFooterLoadingIndicator: Bool {
        isBusy && (displayedStep == .workingRelationship || displayedStep == .tonePreferences)
    }

    @ViewBuilder
    var standardBackButton: some View {
        if canGoBack {
            Button("Back") {
                goBack()
            }
            .buttonStyle(.plain)
            .appFont(.bodySemibold)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Back")
        }
    }
}
