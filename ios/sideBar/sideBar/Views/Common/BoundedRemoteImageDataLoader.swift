import Foundation

enum BoundedRemoteImageDataLoader {
    static func load(
        url: URL,
        session: URLSession = .shared,
        maxBytes: Int64,
        cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad,
        timeoutInterval: TimeInterval = 30
    ) async throws -> Data? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }

        let request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
        let (temporaryURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard isSupportedImageResponse(response),
              response.expectedContentLength <= maxBytes else {
            return nil
        }
        let fileSize = try fileSize(at: temporaryURL)
        guard fileSize <= maxBytes else {
            return nil
        }
        return try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
    }

    private static func isSupportedImageResponse(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else {
            return true
        }
        return (200..<300).contains(http.statusCode) && http.isImageResponse
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private extension HTTPURLResponse {
    var isImageResponse: Bool {
        guard let mimeType = mimeType?.lowercased() else {
            return true
        }
        return mimeType.hasPrefix("image/")
    }
}
