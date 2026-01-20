import Foundation
import OSLog
import Security

public final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    private let pinnedCertificates: Set<Data>
    private let logger = Logger(subsystem: "sideBar", category: "Network")

    public init(pinnedCertificates: Set<Data>) {
        self.pinnedCertificates = pinnedCertificates
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

        guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let serverCertData = SecCertificateCopyData(certificate) as Data
        guard pinnedCertificates.contains(serverCertData) else {
            logger.error("Certificate pinning failed for host: \(challenge.protectionSpace.host, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

public enum PinnedCertificates {
    public static func loadFromMainBundle() -> Set<Data> {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "cer", subdirectory: nil) else {
            return []
        }
        let certs = urls.compactMap { try? Data(contentsOf: $0) }
        return Set(certs)
    }
}
