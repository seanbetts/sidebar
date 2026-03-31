import Foundation

enum PasswordStrengthRules {
    static let minimumLength = 8
    static let guidanceMessage = "Use 8+ characters with upper and lower case, a number, and a symbol."

    static func score(for candidate: String) -> Int {
        guard candidate.count >= minimumLength else { return 0 }

        var score = 1
        if candidate.rangeOfCharacter(from: .uppercaseLetters) != nil &&
            candidate.rangeOfCharacter(from: .lowercaseLetters) != nil {
            score += 1
        }
        if candidate.rangeOfCharacter(from: .decimalDigits) != nil {
            score += 1
        }

        let specials = CharacterSet.alphanumerics.inverted
        if candidate.unicodeScalars.contains(where: { specials.contains($0) }) {
            score += 1
        }
        return score
    }
}
