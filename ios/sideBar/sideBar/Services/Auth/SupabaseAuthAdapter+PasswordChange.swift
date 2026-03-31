import Foundation

@MainActor
extension SupabaseAuthAdapter: PasswordChanging {
    public func changePassword(newPassword: String) async throws {
        try await authClient.updatePassword(validatedPasswordForMutation(newPassword))
    }
}
