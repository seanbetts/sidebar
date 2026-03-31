import Foundation

@MainActor
extension SupabaseAuthAdapter: PasswordRecoveryManaging {
    public func startRecoverySession(from url: URL) async throws {
        let session = try await authClient.session(from: url)
        applySession(session)
    }

    public func completePasswordReset(newPassword: String) async throws {
        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPassword.count >= 8 else {
            throw AuthAdapterError.weakPassword
        }
        try await authClient.updatePassword(trimmedPassword)
    }
}
