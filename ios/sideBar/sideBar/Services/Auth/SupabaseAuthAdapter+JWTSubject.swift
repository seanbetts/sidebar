import Foundation

extension SupabaseAuthAdapter {
    static func jwtSubject(from accessToken: String) -> String? {
        guard let payloadData = decodeJwtPayload(accessToken) else {
            return nil
        }
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: payloadData, options: []),
            let payload = jsonObject as? [String: Any]
        else {
            return nil
        }
        guard let subject = payload["sub"] as? String else {
            return nil
        }
        let trimmed = subject.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
