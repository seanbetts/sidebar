import Foundation
@testable import sideBar

final class DelayedOnboardingAPI: OnboardingProviding {
    private let base = MockOnboardingAPI()
    var getResult: Result<OnboardingState, Error> {
        get { base.getResult }
        set { base.getResult = newValue }
    }
    var updateResult: Result<OnboardingState, Error> {
        get { base.updateResult }
        set { base.updateResult = newValue }
    }
    var submitCalibrationAnswerResult: Result<OnboardingCalibrationActionResponse, Error> {
        get { base.submitCalibrationAnswerResult }
        set { base.submitCalibrationAnswerResult = newValue }
    }
    var submitCalibrationAnswerResults: [Result<OnboardingCalibrationActionResponse, Error>] {
        get { base.submitCalibrationAnswerResults }
        set { base.submitCalibrationAnswerResults = newValue }
    }
    var regenerateCalibrationNameResult: Result<OnboardingCalibrationActionResponse, Error> {
        get { base.regenerateCalibrationNameResult }
        set { base.regenerateCalibrationNameResult = newValue }
    }
    var acceptCalibrationNameResult: Result<OnboardingCalibrationActionResponse, Error> {
        get { base.acceptCalibrationNameResult }
        set { base.acceptCalibrationNameResult = newValue }
    }
    var updateDelayNanoseconds: UInt64 = 0
    var submitDelayNanoseconds: UInt64 = 0
    var regenerateDelayNanoseconds: UInt64 = 0
    var shouldSuspendSubmitUntilResumed: Bool = false
    var shouldSuspendRegenerateUntilResumed: Bool = false
    var onUpdateStarted: (() -> Void)?
    var onUpdateCompleted: (() -> Void)?
    var onSubmitStarted: (() -> Void)?
    var onSubmitCompleted: (() -> Void)?
    var onRegenerateStarted: (() -> Void)?
    var onRegenerateCompleted: (() -> Void)?
    private var submitContinuation: CheckedContinuation<Void, Never>?
    private var regenerateContinuation: CheckedContinuation<Void, Never>?
    private var submitResumeRequested = false
    private var regenerateResumeRequested = false

    private(set) var updates: [MockOnboardingAPI.RecordedUpdate] = []
    var submittedCalibrationAnswers: [(prompt: OnboardingCalibrationPrompt, answer: OnboardingCalibrationAnswer)] {
        base.submittedCalibrationAnswers
    }

    func resumeSubmit() {
        if let submitContinuation {
            self.submitContinuation = nil
            submitContinuation.resume()
            return
        }
        submitResumeRequested = true
    }

    func resumeRegenerate() {
        if let regenerateContinuation {
            self.regenerateContinuation = nil
            regenerateContinuation.resume()
            return
        }
        regenerateResumeRequested = true
    }

    func getOnboarding() async throws -> OnboardingState {
        try await base.getOnboarding()
    }

    func updateOnboarding(_ update: OnboardingUpdate) async throws -> OnboardingState {
        onUpdateStarted?()
        if updateDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: updateDelayNanoseconds)
        }
        let state = try await base.updateOnboarding(update)
        updates = base.updates
        onUpdateCompleted?()
        return state
    }

    func submitCalibrationAnswer(
        _ prompt: OnboardingCalibrationPrompt,
        answer: OnboardingCalibrationAnswer
    ) async throws -> OnboardingCalibrationActionResponse {
        onSubmitStarted?()
        if submitDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: submitDelayNanoseconds)
        }
        if shouldSuspendSubmitUntilResumed {
            if submitResumeRequested {
                submitResumeRequested = false
            } else {
                await withCheckedContinuation { continuation in
                    submitContinuation = continuation
                }
            }
        }
        defer { onSubmitCompleted?() }
        return try await base.submitCalibrationAnswer(prompt, answer: answer)
    }

    func regenerateCalibrationName() async throws -> OnboardingCalibrationActionResponse {
        onRegenerateStarted?()
        if regenerateDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: regenerateDelayNanoseconds)
        }
        if shouldSuspendRegenerateUntilResumed {
            if regenerateResumeRequested {
                regenerateResumeRequested = false
            } else {
                await withCheckedContinuation { continuation in
                    regenerateContinuation = continuation
                }
            }
        }
        defer { onRegenerateCompleted?() }
        return try await base.regenerateCalibrationName()
    }

    func acceptCalibrationName() async throws -> OnboardingCalibrationActionResponse {
        try await base.acceptCalibrationName()
    }
}
