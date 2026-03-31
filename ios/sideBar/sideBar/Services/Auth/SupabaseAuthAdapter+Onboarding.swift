import Foundation
import os

@MainActor
extension SupabaseAuthAdapter {
    public func signUp(email: String, password: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPassword = try validatedPasswordForMutation(password)

        do {
            try await authClient.signUp(email: trimmedEmail, password: trimmedPassword)
            pendingVerificationEmail = trimmedEmail
            logger.notice("Sign up succeeded for pending verification")
        } catch {
            let mappedError = mapAuthError(error)
            logger.error("Sign up failed: \(mappedError.localizedDescription, privacy: .public)")
            throw mappedError
        }
    }

    public func verifyOTP(email: String, code: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let session = try await authClient.verifyOTP(email: trimmedEmail, code: trimmedCode)
            applySession(session)
            pendingVerificationEmail = nil
            logger.notice("OTP verification succeeded")
        } catch {
            let mappedError = mapAuthError(error)
            logger.error("OTP verification failed: \(mappedError.localizedDescription, privacy: .public)")
            throw mappedError
        }
    }
}
