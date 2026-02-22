import Foundation
import CryptoKit
import OSLog
import Security

/// URLSession delegate that enforces certificate pinning in production.
public final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    private let pinnedCertificates: Set<Data>
    private let pinnedPublicKeyHashes: Set<Data>
    private let pinnedHostPatterns: [String]
    private let logger = Logger(subsystem: "sideBar", category: "Network")

    public init(pinnedCertificates: Set<Data>) {
        self.pinnedCertificates = pinnedCertificates
        self.pinnedPublicKeyHashes = Set(
            pinnedCertificates.compactMap { Self.publicKeyHash(fromCertificateData: $0) }
        )
        self.pinnedHostPatterns = pinnedCertificates.compactMap { certData in
            guard let summary = Self.subjectSummary(fromCertificateData: certData) else {
                return nil
            }
            return Self.normalizedHostPattern(from: summary)
        }
        super.init()
        let certCount = pinnedCertificates.count
        let keyCount = pinnedPublicKeyHashes.count
        let patterns = pinnedHostPatterns
        let patternList = patterns.joined(separator: ", ")
        logger.info(
            "CertPin: \(certCount) cert(s), \(keyCount) key hash(es), patterns=[\(patternList, privacy: .public)]"
        )
        if keyCount == 0 && certCount > 0 {
            logger.warning("CertPin: no public key hashes extracted — key-hash fallback disabled")
        }
        if patterns.isEmpty && certCount > 0 {
            logger.warning("CertPin: no host patterns parsed — pinning will apply to ALL HTTPS hosts")
        }
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host.lowercased()
        if shouldBypassPinning(forHost: host) {
            logger.debug("CertPin: bypassing \(host, privacy: .public) — not in pinned patterns")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            logger.error("CertPin: no serverTrust for \(host, privacy: .public) — cancelling")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            let reason = trustError?.localizedDescription ?? "unknown"
            logger.error(
                "CertPin: TLS trust eval failed for \(host, privacy: .public): \(reason, privacy: .public)"
            )
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let certificate = leafCertificate(from: serverTrust) else {
            logger.error("CertPin: could not extract leaf cert for \(host, privacy: .public) — cancelling")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certMatch = isPinnedCertificateMatch(certificate)
        let keyMatch = !certMatch && isPinnedPublicKeyMatch(certificate)
        guard certMatch || keyMatch else {
            let bundledCerts = pinnedCertificates.count
            let keyHashes = pinnedPublicKeyHashes.count
            logger.error(
                // swiftlint:disable:next line_length
                "CertPin: pin mismatch for \(host, privacy: .public) — certMatch=\(certMatch) keyMatch=\(keyMatch) bundledCerts=\(bundledCerts) keyHashes=\(keyHashes)"
            )
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        logger.debug("CertPin: validated \(host, privacy: .public) via \(certMatch ? "cert" : "key-hash", privacy: .public)")
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func shouldBypassPinning(forHost host: String) -> Bool {
        guard !pinnedHostPatterns.isEmpty else { return false }
        return !pinnedHostPatterns.contains { Self.hostMatchesPinnedPattern(host: host, pattern: $0) }
    }

    private func isPinnedCertificateMatch(_ certificate: SecCertificate) -> Bool {
        let serverCertData = SecCertificateCopyData(certificate) as Data
        return pinnedCertificates.contains(serverCertData)
    }

    private func isPinnedPublicKeyMatch(_ certificate: SecCertificate) -> Bool {
        guard let serverKeyHash = Self.publicKeyHash(from: certificate) else {
            return false
        }
        return pinnedPublicKeyHashes.contains(serverKeyHash)
    }

    private func leafCertificate(from trust: SecTrust) -> SecCertificate? {
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
        return chain?.first
    }

    public static func hostMatchesPinnedPattern(host: String, pattern: String) -> Bool {
        let normalizedHost = host.lowercased()
        let normalizedPattern = pattern.lowercased()
        if normalizedPattern.hasPrefix("*.") {
            let suffix = String(normalizedPattern.dropFirst(2))
            guard !suffix.isEmpty else { return false }
            return normalizedHost.hasSuffix(".\(suffix)")
        }
        return normalizedHost == normalizedPattern
    }

    private static func subjectSummary(fromCertificateData data: Data) -> String? {
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            return nil
        }
        return SecCertificateCopySubjectSummary(certificate) as String?
    }

    // Internal for unit testing.
    static func normalizedHostPattern(from summary: String) -> String? {
        let pattern = summary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !pattern.isEmpty else { return nil }
        let base = pattern.hasPrefix("*.") ? String(pattern.dropFirst(2)) : pattern
        guard base.contains(".") else { return nil }
        // Validate only the base domain; the "*.'" wildcard prefix is intentionally permitted.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard base.rangeOfCharacter(from: allowed.inverted) == nil else {
            return nil
        }
        return pattern
    }

    private static func publicKeyHash(fromCertificateData data: Data) -> Data? {
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            return nil
        }
        return publicKeyHash(from: certificate)
    }

    private static func publicKeyHash(from certificate: SecCertificate) -> Data? {
        guard let key = SecCertificateCopyKey(certificate) else {
            Logger(subsystem: "sideBar", category: "Network")
                .warning("CertPin: SecCertificateCopyKey returned nil — key-hash unavailable for this cert")
            return nil
        }
        var copyError: Unmanaged<CFError>?
        guard let rawKey = SecKeyCopyExternalRepresentation(key, &copyError) as Data? else {
            let reason = copyError?.takeRetainedValue().localizedDescription ?? "unknown"
            Logger(subsystem: "sideBar", category: "Network")
                .warning("CertPin: SecKeyCopyExternalRepresentation failed (\(reason, privacy: .public)) — key-hash unavailable")
            return nil
        }
        return Data(SHA256.hash(data: rawKey))
    }
}

/// Defines PinnedCertificates.
public enum PinnedCertificates {
    public static func loadFromMainBundle() -> Set<Data> {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "cer", subdirectory: nil) else {
            return []
        }
        let certs = urls.compactMap { try? Data(contentsOf: $0) }
        return Set(certs)
    }
}
