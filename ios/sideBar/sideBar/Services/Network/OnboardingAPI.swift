import Foundation
import sideBarShared

/// Defines the requirements for onboarding state reads and writes.
public protocol OnboardingProviding {
    func getOnboarding() async throws -> OnboardingState
    func updateOnboarding(_ update: OnboardingUpdate) async throws -> OnboardingState
}

/// API client for backend onboarding endpoints.
public struct OnboardingAPI {
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
}
