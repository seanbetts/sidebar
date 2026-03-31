import Foundation

extension SupabaseAuthAdapter {
    static func jwtSubject(from accessToken: String) -> String? {
        JWTClaims.subject(from: accessToken)
    }
}
