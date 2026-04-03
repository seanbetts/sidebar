import Foundation
import sideBarShared

/// Defines the requirements for onboarding state reads and writes.
public protocol OnboardingProviding {
    func getOnboarding() async throws -> OnboardingState
    func updateOnboarding(_ update: OnboardingUpdate) async throws -> OnboardingState
    func submitCalibrationAnswer(
        _ prompt: OnboardingCalibrationPrompt,
        answer: OnboardingCalibrationAnswer
    ) async throws -> OnboardingCalibrationActionResponse
    func regenerateCalibrationName() async throws -> OnboardingCalibrationActionResponse
    func acceptCalibrationName() async throws -> OnboardingCalibrationActionResponse
}

/// API client for backend onboarding endpoints.
public struct OnboardingAPI {
    static let calibrationRequestTimeoutInterval: TimeInterval = 90

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }
}

extension OnboardingAPI: OnboardingProviding {
    public func getOnboarding() async throws -> OnboardingState {
        try await client.request("onboarding")
    }

    public func updateOnboarding(_ update: OnboardingUpdate) async throws -> OnboardingState {
        try await client.request("onboarding", method: "PATCH", body: update)
    }

    public func submitCalibrationAnswer(
        _ prompt: OnboardingCalibrationPrompt,
        answer: OnboardingCalibrationAnswer
    ) async throws -> OnboardingCalibrationActionResponse {
        try await client.request(
            "onboarding/calibration/respond",
            method: "POST",
            body: CalibrationRespondRequest(prompt: prompt, answer: answer.requestValue),
            timeoutInterval: Self.calibrationRequestTimeoutInterval
        )
    }

    public func regenerateCalibrationName() async throws -> OnboardingCalibrationActionResponse {
        try await client.request(
            "onboarding/calibration/name/regenerate",
            method: "POST",
            body: CalibrationNameActionRequest(),
            timeoutInterval: Self.calibrationRequestTimeoutInterval
        )
    }

    public func acceptCalibrationName() async throws -> OnboardingCalibrationActionResponse {
        try await client.request(
            "onboarding/calibration/name/accept",
            method: "POST",
            body: CalibrationNameActionRequest(),
            timeoutInterval: Self.calibrationRequestTimeoutInterval
        )
    }
}

private struct CalibrationRespondRequest: Encodable {
    let prompt: OnboardingCalibrationPrompt
    let answer: String
}

private struct CalibrationNameActionRequest: Encodable {}
