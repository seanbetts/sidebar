import Foundation

struct PasswordFormValidation {
    let newPassword: String
    let confirmPassword: String

    var strengthScore: Int {
        PasswordStrengthRules.score(for: newPassword)
    }

    var hasMinimumPasswordLength: Bool {
        newPassword.count >= PasswordStrengthRules.minimumLength
    }

    var passwordMismatchMessage: String? {
        guard !confirmPassword.isEmpty, newPassword != confirmPassword else {
            return nil
        }
        return "Passwords don't match."
    }

    func canSubmit(isSubmitting: Bool) -> Bool {
        !isSubmitting
            && hasMinimumPasswordLength
            && !confirmPassword.isEmpty
            && passwordMismatchMessage == nil
    }
}
