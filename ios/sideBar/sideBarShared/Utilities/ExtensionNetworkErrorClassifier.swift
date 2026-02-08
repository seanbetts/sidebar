import Foundation

public enum ExtensionNetworkErrorClassifier {
    public static func isOfflineLike(_ error: Error) -> Bool {
        messageCode(for: error) == .networkError
    }

    public static func messageCode(for error: Error) -> ExtensionMessageCode? {
        guard let code = urlErrorCode(from: error) else {
            return nil
        }

        switch code {
        case .timedOut,
             .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost:
            return .networkError
        default:
            return nil
        }
    }

    private static func urlErrorCode(from error: Error) -> URLError.Code? {
        if let urlError = error as? URLError {
            return urlError.code
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }
        return URLError.Code(rawValue: nsError.code)
    }
}
