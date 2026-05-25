import Foundation

/// Updates a password for an already authenticated session.
@MainActor public protocol PasswordChanging: AnyObject {
    /// Changes the password for the current authenticated user.
    func changePassword(newPassword: String) async throws
}

func validatedPasswordForMutation(_ candidate: String) throws -> String {
    guard candidate.count >= PasswordStrengthRules.minimumLength else {
        throw AuthAdapterError.weakPassword
    }
    return candidate
}
