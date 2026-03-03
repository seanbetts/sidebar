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

    private let lock = NSLock()
    private var records: [String: Date] = [:]
    let ttl: TimeInterval  // internal for testing

    init(ttl: TimeInterval = 5) {
        self.ttl = ttl
    }

    /// Records that certificate pinning rejected the given host.
    public func record(host: String) {
        let normalizedHost = normalize(host)
        lock.lock()
        records[normalizedHost] = Date()
        lock.unlock()
    }

    /// Returns true if a pinning cancellation was recorded for `host` within the TTL window.
    public func wasCancelled(host: String) -> Bool {
        let normalizedHost = normalize(host)
        let now = Date()

        lock.lock()
        defer { lock.unlock() }

        guard let recordedAt = records[normalizedHost] else {
            return false
        }
        let isWithinTTL = now.timeIntervalSince(recordedAt) <= ttl
        if !isWithinTTL {
            records.removeValue(forKey: normalizedHost)
        }
        return isWithinTTL
    }

    private func normalize(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
