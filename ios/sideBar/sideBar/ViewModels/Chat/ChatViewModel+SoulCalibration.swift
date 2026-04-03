import Foundation

extension ChatViewModel {
    public var canShowFeatureDiscovery: Bool {
        soulCalibrationState == nil
    }

    func syncSoulCalibration(from onboardingState: OnboardingState?) {
        guard let onboardingState,
              onboardingState.currentOnboardingStep == .soulCalibration else {
            soulCalibrationState = nil
            soulCalibrationConfirmationText = nil
            soulCalibrationErrorMessage = nil
            isSubmittingSoulCalibration = false
            return
        }

        soulCalibrationState = onboardingState.calibration
        if onboardingState.calibration.status != .awaitingNameAcceptance {
            soulCalibrationConfirmationText = nil
        }
    }

    func submitSoulCalibrationAnswer(_ answer: OnboardingCalibrationAnswer) async {
        guard let currentState = soulCalibrationState,
              let onboardingAPI else {
            soulCalibrationErrorMessage = "Soul calibration is unavailable right now."
            return
        }

        await submitSoulCalibrationAnswer(
            prompt: currentState.currentPrompt,
            answer
        )
    }

    func submitSoulCalibrationAnswer(
        prompt: OnboardingCalibrationPrompt,
        _ answer: OnboardingCalibrationAnswer
    ) async {
        guard let onboardingAPI else {
            soulCalibrationErrorMessage = "Soul calibration is unavailable right now."
            return
        }

        isSubmittingSoulCalibration = true
        soulCalibrationErrorMessage = nil
        defer { isSubmittingSoulCalibration = false }

        do {
            let response = try await onboardingAPI.submitCalibrationAnswer(
                prompt,
                answer: answer
            )
            applySoulCalibration(response: response)
        } catch {
            soulCalibrationErrorMessage = ErrorMapping.message(for: error)
        }
    }

    func regenerateSoulCalibrationName() async {
        guard let onboardingAPI else {
            soulCalibrationErrorMessage = "Soul calibration is unavailable right now."
            return
        }

        isSubmittingSoulCalibration = true
        soulCalibrationErrorMessage = nil
        defer { isSubmittingSoulCalibration = false }

        do {
            let response = try await onboardingAPI.regenerateCalibrationName()
            applySoulCalibration(response: response)
        } catch {
            soulCalibrationErrorMessage = ErrorMapping.message(for: error)
        }
    }

    func acceptSoulCalibrationName() async {
        guard let onboardingAPI else {
            soulCalibrationErrorMessage = "Soul calibration is unavailable right now."
            return
        }

        isSubmittingSoulCalibration = true
        soulCalibrationErrorMessage = nil
        defer { isSubmittingSoulCalibration = false }

        do {
            let response = try await onboardingAPI.acceptCalibrationName()
            applySoulCalibration(response: response)
        } catch {
            soulCalibrationErrorMessage = ErrorMapping.message(for: error)
        }
    }

    private func applySoulCalibration(response: OnboardingCalibrationActionResponse) {
        if response.state.currentOnboardingStep == .soulCalibration {
            soulCalibrationState = response.calibration
            soulCalibrationConfirmationText = response.confirmationText
        } else {
            soulCalibrationState = nil
            soulCalibrationConfirmationText = nil
        }

        if response.assistantIdentity != nil || response.assistantSoul != nil {
            onAssistantSettingsUpdated?(
                AssistantSettingsRealtimeUpdate(
                    assistantIdentity: response.assistantIdentity,
                    assistantIdentityMeta: nil,
                    assistantSoul: response.assistantSoul,
                    assistantSoulMeta: nil,
                    requiresRefresh: false
                )
            )
        }

        requestOnboardingStateRefresh()
    }
}
