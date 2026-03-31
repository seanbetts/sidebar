import Foundation

@MainActor
/// Updates a password for an already authenticated session.
public protocol PasswordChanging: AnyObject {
    /// Changes the password for the current authenticated user.
    func changePassword(newPassword: String) async throws
}

func validatedPasswordForMutation(_ candidate: String) throws -> String {
    let trimmedPassword = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedPassword.count >= PasswordStrengthRules.minimumLength else {
        throw AuthAdapterError.weakPassword
    }
    return trimmedPassword
}
