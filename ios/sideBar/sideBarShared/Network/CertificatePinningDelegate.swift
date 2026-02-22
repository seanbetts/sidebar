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
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            logger.error("TLS trust evaluation failed: \(trustError?.localizedDescription ?? "unknown", privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let certificate = leafCertificate(from: serverTrust) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard isPinnedCertificateMatch(certificate) || isPinnedPublicKeyMatch(certificate) else {
            logger.error("Certificate pinning failed for host: \(challenge.protectionSpace.host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

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

    private static func normalizedHostPattern(from summary: String) -> String? {
        let pattern = summary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !pattern.isEmpty else { return nil }
        let base = pattern.hasPrefix("*.") ? String(pattern.dropFirst(2)) : pattern
        guard base.contains(".") else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard pattern.rangeOfCharacter(from: allowed.inverted) == nil else {
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
            return nil
        }
        var copyError: Unmanaged<CFError>?
        guard let rawKey = SecKeyCopyExternalRepresentation(key, &copyError) as Data? else {
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
