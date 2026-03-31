import Foundation

enum JWTClaims {
    static func subject(from accessToken: String) -> String? {
        guard let payloadData = decodeJwtPayload(accessToken) else {
            return nil
        }
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: payloadData, options: []),
            let payload = jsonObject as? [String: Any],
            let subject = payload["sub"] as? String
        else {
            return nil
        }

        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeJwtPayload(_ token: String) -> Data? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        return base64URLDecode(String(segments[1]))
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: base64)
    }
}
