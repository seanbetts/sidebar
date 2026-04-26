import Foundation

@MainActor
extension SupabaseAuthAdapter: PasswordRecoveryManaging {
    public func startRecoverySession(from url: URL) async throws {
        let session = try await authClient.session(from: url)
        applySession(session, allowsReauthenticationRecovery: true)
    }

    public func completePasswordReset(newPassword: String) async throws {
        try await authClient.updatePassword(try validatedPasswordForMutation(newPassword))
    }
}
