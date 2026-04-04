import Foundation
import sideBarShared

extension ChatViewModel {
    public var canShowFeatureDiscovery: Bool {
        soulCalibrationState == nil
    }

    public var shouldShowSoulCalibrationIntro: Bool {
        guard let soulCalibrationState else {
            return false
        }
        guard !hasAcknowledgedSoulCalibrationIntro else {
            return false
        }
        guard soulCalibrationState.status != .awaitingNameAcceptance,
              soulCalibrationState.currentPrompt == .primaryGoal else {
            return false
        }
        return !hasStartedSoulCalibrationQuestions(soulCalibrationState)
    }

    func syncSoulCalibration(from onboardingState: OnboardingState?) {
        guard let onboardingState,
              onboardingState.currentOnboardingStep == .soulCalibration else {
            soulCalibrationState = nil
            soulCalibrationConfirmationText = nil
            soulCalibrationErrorMessage = nil
            isSubmittingSoulCalibration = false
            hasAcknowledgedSoulCalibrationIntro = false
            pendingSoulCalibrationSubmission = nil
            return
        }

        soulCalibrationState = onboardingState.calibration
        if shouldAutoAcknowledgeSoulCalibrationIntro(
            for: onboardingState.calibration
        ) {
            hasAcknowledgedSoulCalibrationIntro = true
        }
        if onboardingState.calibration.status != .awaitingNameAcceptance {
            soulCalibrationConfirmationText = nil
        }
    }

    func acknowledgeSoulCalibrationIntro() {
        hasAcknowledgedSoulCalibrationIntro = true
        soulCalibrationErrorMessage = nil
    }

    func submitSoulCalibrationAnswer(_ answer: OnboardingCalibrationAnswer) async {
        guard let currentState = soulCalibrationState else {
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

        if isSubmittingSoulCalibration {
            pendingSoulCalibrationSubmission = PendingSoulCalibrationSubmission(
                prompt: prompt,
                answer: answer
            )
            soulCalibrationErrorMessage = nil
            return
        }

        isSubmittingSoulCalibration = true
        pendingSoulCalibrationSubmission = nil
        soulCalibrationErrorMessage = nil

        do {
            let response = try await submitSoulCalibrationAnswerWithRecovery(
                prompt,
                answer: answer,
                using: onboardingAPI
            )
            if shouldGenerateInitialSoulCalibrationName(after: response) {
                do {
                    applyAssistantSettingsUpdate(from: response)
                    let nameResponse = try await regenerateSoulCalibrationNameWithRecovery(
                        using: onboardingAPI
                    )
                    applySoulCalibration(response: nameResponse)
                } catch {
                    soulCalibrationErrorMessage = soulCalibrationMessage(for: error)
                }
            } else {
                applySoulCalibration(response: response)
            }
            isSubmittingSoulCalibration = false
            await submitPendingSoulCalibrationSubmissionIfNeeded()
        } catch {
            isSubmittingSoulCalibration = false
            pendingSoulCalibrationSubmission = nil
            soulCalibrationErrorMessage = soulCalibrationMessage(for: error)
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
            let response = try await regenerateSoulCalibrationNameWithRecovery(
                using: onboardingAPI
            )
            applySoulCalibration(response: response)
        } catch {
            soulCalibrationErrorMessage = soulCalibrationMessage(for: error)
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
            soulCalibrationErrorMessage = soulCalibrationMessage(for: error)
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

        applyAssistantSettingsUpdate(from: response)

        requestOnboardingStateRefresh()
    }

    private func applyAssistantSettingsUpdate(from response: OnboardingCalibrationActionResponse) {
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
    }

    private func shouldGenerateInitialSoulCalibrationName(
        after response: OnboardingCalibrationActionResponse
    ) -> Bool {
        response.calibration.status == .awaitingNameAcceptance
            && (response.calibration.proposedName?.isEmpty ?? true)
    }

    private func submitSoulCalibrationAnswerWithRecovery(
        _ prompt: OnboardingCalibrationPrompt,
        answer: OnboardingCalibrationAnswer,
        using onboardingAPI: any OnboardingProviding
    ) async throws -> OnboardingCalibrationActionResponse {
        do {
            return try await onboardingAPI.submitCalibrationAnswer(prompt, answer: answer)
        } catch {
            if let onboardingState = try await recoverCalibrationState(
                after: error,
                using: onboardingAPI
            ) {
                if let recovered = recoveredSubmitResponse(
                    from: onboardingState,
                    prompt: prompt
                ) {
                    return recovered
                }

                if shouldRetrySoulCalibrationSubmit(
                    after: error,
                    currentState: onboardingState,
                    prompt: prompt
                ) {
                    try await sleepBeforeSoulCalibrationRetry()
                    do {
                        return try await onboardingAPI.submitCalibrationAnswer(prompt, answer: answer)
                    } catch {
                        if let retryState = try await recoverCalibrationState(
                            after: error,
                            using: onboardingAPI
                        ),
                           let recovered = recoveredSubmitResponse(
                               from: retryState,
                               prompt: prompt
                           ) {
                            return recovered
                        }
                        throw error
                    }
                }
            }
            throw error
        }
    }

    private func regenerateSoulCalibrationNameWithRecovery(
        using onboardingAPI: any OnboardingProviding
    ) async throws -> OnboardingCalibrationActionResponse {
        do {
            return try await onboardingAPI.regenerateCalibrationName()
        } catch {
            if let onboardingState = try await recoverCalibrationState(
                after: error,
                using: onboardingAPI
            ) {
                if let recovered = recoveredNameRegenerationResponse(from: onboardingState) {
                    return recovered
                }

                if shouldRetrySoulCalibrationNameRegeneration(
                    after: error,
                    currentState: onboardingState
                ) {
                    try await sleepBeforeSoulCalibrationRetry()
                    do {
                        return try await onboardingAPI.regenerateCalibrationName()
                    } catch {
                        if let retryState = try await recoverCalibrationState(
                            after: error,
                            using: onboardingAPI
                        ),
                           let recovered = recoveredNameRegenerationResponse(from: retryState) {
                            return recovered
                        }
                        throw error
                    }
                }
            }
            throw error
        }
    }

    private func recoverCalibrationState(
        after error: Error,
        using onboardingAPI: any OnboardingProviding
    ) async throws -> OnboardingState? {
        guard shouldCheckCalibrationStateAfterError(error) else {
            return nil
        }
        return try await onboardingAPI.getOnboarding()
    }

    private func recoveredSubmitResponse(
        from onboardingState: OnboardingState,
        prompt: OnboardingCalibrationPrompt
    ) -> OnboardingCalibrationActionResponse? {
        if onboardingState.currentOnboardingStep != .soulCalibration {
            guard onboardingState.currentOnboardingStep == .featureDiscovery
                || onboardingState.currentOnboardingStep == .completed
                || onboardingState.calibration.status == .completed else {
                return nil
            }
            return synthesizedCalibrationResponse(from: onboardingState)
        }

        switch onboardingState.calibration.status {
        case .awaitingNameAcceptance, .completed:
            return synthesizedCalibrationResponse(from: onboardingState)
        case .inProgress:
            guard calibrationPromptIndex(onboardingState.calibration.currentPrompt)
                > calibrationPromptIndex(prompt) else {
                return nil
            }
            return synthesizedCalibrationResponse(from: onboardingState)
        case .notStarted:
            return nil
        }
    }

    private func recoveredNameRegenerationResponse(
        from onboardingState: OnboardingState
    ) -> OnboardingCalibrationActionResponse? {
        if onboardingState.currentOnboardingStep != .soulCalibration {
            guard onboardingState.currentOnboardingStep == .featureDiscovery
                || onboardingState.currentOnboardingStep == .completed
                || onboardingState.calibration.status == .completed else {
                return nil
            }
            return synthesizedCalibrationResponse(from: onboardingState)
        }

        if onboardingState.calibration.status == .completed {
            return synthesizedCalibrationResponse(from: onboardingState)
        }

        guard onboardingState.calibration.status == .awaitingNameAcceptance,
              hasNonEmptySoulCalibrationText(onboardingState.calibration.proposedName) else {
            return nil
        }

        return synthesizedCalibrationResponse(
            from: onboardingState,
            confirmationText: "How about \(onboardingState.calibration.proposedName ?? "")?"
        )
    }

    private func synthesizedCalibrationResponse(
        from onboardingState: OnboardingState,
        confirmationText: String? = nil
    ) -> OnboardingCalibrationActionResponse {
        OnboardingCalibrationActionResponse(
            state: onboardingState,
            calibration: onboardingState.calibration,
            assistantIdentity: nil,
            assistantSoul: nil,
            confirmationText: confirmationText
        )
    }

    private func shouldCheckCalibrationStateAfterError(_ error: Error) -> Bool {
        isSoulCalibrationConflictError(error) || isRetryableSoulCalibrationError(error)
    }

    private func shouldRetrySoulCalibrationSubmit(
        after error: Error,
        currentState: OnboardingState,
        prompt: OnboardingCalibrationPrompt
    ) -> Bool {
        isRetryableSoulCalibrationError(error)
            && currentState.currentOnboardingStep == .soulCalibration
            && currentState.calibration.status == .inProgress
            && currentState.calibration.currentPrompt == prompt
    }

    private func shouldRetrySoulCalibrationNameRegeneration(
        after error: Error,
        currentState: OnboardingState
    ) -> Bool {
        (isRetryableSoulCalibrationError(error) || isSoulCalibrationConflictError(error))
            && currentState.currentOnboardingStep == .soulCalibration
            && currentState.calibration.status == .awaitingNameAcceptance
            && !hasNonEmptySoulCalibrationText(currentState.calibration.proposedName)
    }

    private func isRetryableSoulCalibrationError(_ error: Error) -> Bool {
        if URLRequestErrorClassifier.category(for: error) == .timeout {
            return true
        }

        guard let apiError = error as? APIClientError else {
            return false
        }

        switch apiError {
        case .apiError(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed == "database request timed out"
        case .requestFailed(let status):
            return [408, 429, 502, 503, 504].contains(status)
        case .missingToken, .decodingFailed, .invalidUrl, .unknown:
            return false
        @unknown default:
            return false
        }
    }

    private func isSoulCalibrationConflictError(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else {
            return false
        }

        switch apiError {
        case .apiError(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed.hasPrefix("Expected prompt ")
                && trimmed.split(separator: " ").count >= 3)
                || trimmed == "Calibration is not awaiting name acceptance"
        case .requestFailed(let status):
            return status == 409
        case .missingToken, .decodingFailed, .invalidUrl, .unknown:
            return false
        @unknown default:
            return false
        }
    }

    private func soulCalibrationMessage(for error: Error) -> String {
        if isSoulCalibrationConflictError(error) {
            return "I got out of sync with your setup. Please go back and try again."
        }
        return ErrorMapping.message(for: error)
    }

    private func calibrationPromptIndex(_ prompt: OnboardingCalibrationPrompt) -> Int {
        switch prompt {
        case .primaryGoal:
            return 0
        case .workingRelationship:
            return 1
        case .tonePreferences:
            return 2
        }
    }

    private func hasNonEmptySoulCalibrationText(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hasStartedSoulCalibrationQuestions(
        _ state: OnboardingCalibrationState
    ) -> Bool {
        hasNonEmptySoulCalibrationText(state.answers.primaryGoal)
            || hasNonEmptySoulCalibrationText(state.answers.workingRelationship)
            || hasNonEmptySoulCalibrationText(state.answers.tonePreferences)
    }

    private func shouldAutoAcknowledgeSoulCalibrationIntro(
        for state: OnboardingCalibrationState
    ) -> Bool {
        state.status == .awaitingNameAcceptance
            || state.currentPrompt != .primaryGoal
            || hasStartedSoulCalibrationQuestions(state)
    }

    private func sleepBeforeSoulCalibrationRetry() async throws {
        guard soulCalibrationRetryBackoffNanoseconds > 0 else {
            return
        }
        try await Task.sleep(nanoseconds: soulCalibrationRetryBackoffNanoseconds)
    }

    private func submitPendingSoulCalibrationSubmissionIfNeeded() async {
        guard let pending = pendingSoulCalibrationSubmission else {
            return
        }
        pendingSoulCalibrationSubmission = nil
        await submitSoulCalibrationAnswer(
            prompt: pending.prompt,
            pending.answer
        )
    }
}
