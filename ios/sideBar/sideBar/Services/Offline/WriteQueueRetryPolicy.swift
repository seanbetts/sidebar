import Foundation

enum WriteQueueRetryPolicy {
    static let maximumAttempts: Int16 = 5

    static func shouldRetry(attempts: Int16) -> Bool {
        attempts < maximumAttempts
    }

    static func backoffDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let seconds = min(pow(2.0, Double(max(attempt - 1, 0))), 16.0)
        return UInt64(seconds * 1_000_000_000)
    }

    static func shouldReplayFailedWrite(lastError: String?, conflictReason: String?) -> Bool {
        guard conflictReason == nil, let lastError else {
            return false
        }

        if let statusCode = retryableHTTPStatusCode(from: lastError) {
            return statusCode == 408 || statusCode == 429 || statusCode >= 500
        }

        guard let urlErrorCode = urlErrorCode(from: lastError) else {
            return false
        }

        switch urlErrorCode {
        case URLError.notConnectedToInternet.rawValue,
             URLError.networkConnectionLost.rawValue,
             URLError.timedOut.rawValue,
             URLError.cannotFindHost.rawValue,
             URLError.cannotConnectToHost.rawValue,
             URLError.dnsLookupFailed.rawValue:
            return true
        default:
            return false
        }
    }

    private static func retryableHTTPStatusCode(from errorDescription: String) -> Int? {
        let prefix = "requestFailed("
        guard let range = errorDescription.range(of: prefix) else {
            return nil
        }
        let suffix = errorDescription[range.upperBound...]
        guard let endIndex = suffix.firstIndex(of: ")") else {
            return nil
        }
        return Int(suffix[..<endIndex])
    }

    private static func urlErrorCode(from errorDescription: String) -> Int? {
        let marker = "Code="
        guard errorDescription.contains("NSURLErrorDomain"),
              let codeRange = errorDescription.range(of: marker) else {
            return nil
        }
        let suffix = errorDescription[codeRange.upperBound...]
        let numericPrefix = suffix.prefix { $0 == "-" || $0.isNumber }
        guard !numericPrefix.isEmpty else {
            return nil
        }
        return Int(numericPrefix)
    }
}
