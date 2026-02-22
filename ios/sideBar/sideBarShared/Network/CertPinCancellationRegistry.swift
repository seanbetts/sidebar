import Foundation

/// Thread-safe registry that records hosts where certificate pinning cancelled a TLS challenge.
///
/// ``CertificatePinningDelegate`` records a host here before calling
/// ``URLSession.AuthChallengeDisposition.cancelAuthenticationChallenge``.
/// ``URLRequestErrorClassifier`` queries the registry when a `.cancelled` URLError arrives,
/// allowing the error to be correctly classified as a secure-connection failure rather than
/// a benign request interruption.
public final class CertPinCancellationRegistry {
    /// Shared singleton used by the pinning delegate and error classifier.
    public static let shared = CertPinCancellationRegistry()

    private let cache = NSCache<NSString, NSDate>()
    let ttl: TimeInterval  // internal for testing

    init(ttl: TimeInterval = 5) {
        self.ttl = ttl
    }

    /// Records that certificate pinning rejected the given host.
    public func record(host: String) {
        cache.setObject(NSDate(), forKey: host as NSString)
    }

    /// Returns true if a pinning cancellation was recorded for `host` within the TTL window.
    public func wasCancelled(host: String) -> Bool {
        guard let recorded = cache.object(forKey: host as NSString) else {
            return false
        }
        return Date().timeIntervalSince(recorded as Date) <= ttl
    }
}
