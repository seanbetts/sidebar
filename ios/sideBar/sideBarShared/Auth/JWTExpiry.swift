import Foundation

/// Reads JWT expiry timestamps without validating token signatures.
public enum JWTExpiry {
    /// Returns whether an access token is missing, invalid, or inside the refresh lead time.
    public static func shouldRefreshAccessToken(
        _ accessToken: String,
        now: Date = Date(),
        leadTime: TimeInterval
    ) -> Bool {
        guard let expiry = jwtExpiryDate(from: accessToken) else {
            return true
        }
        return expiry.timeIntervalSince(now) <= leadTime
    }

    private static func jwtExpiryDate(from accessToken: String) -> Date? {
        guard let payloadData = decodeJwtPayload(accessToken) else {
            return nil
        }
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: payloadData, options: []),
            let payload = jsonObject as? [String: Any]
        else {
            return nil
        }
        if let exp = payload["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let expString = payload["exp"] as? String,
           let exp = TimeInterval(expString) {
            return Date(timeIntervalSince1970: exp)
        }
        return nil
    }

    private static func decodeJwtPayload(_ token: String) -> Data? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        let payload = String(segments[1])
        return base64URLDecode(payload)
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
