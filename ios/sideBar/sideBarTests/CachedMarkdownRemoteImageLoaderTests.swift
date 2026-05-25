import XCTest
@testable import sideBar

@MainActor
final class CachedMarkdownRemoteImageLoaderTests: XCTestCase {
    override func tearDown() {
        MarkdownImageURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testRemoteImageLoaderRejectsOversizedDownloads() async {
        let payload = Data(repeating: 0xA, count: 5)
        let loader = CachedMarkdownRemoteImageLoader(
            session: makeSession(data: payload, mimeType: "image/png"),
            maxImageDataBytes: 4
        )

        await loader.load(url: URL(string: "https://example.com/large.png")!)

        guard case .failure = loader.phase else {
            XCTFail("Expected oversized image to fail")
            return
        }
    }

    func testRemoteImageLoaderLoadsSmallImageDownloads() async throws {
        let loader = CachedMarkdownRemoteImageLoader(
            session: makeSession(data: Self.onePixelPNGData, mimeType: "image/png"),
            maxImageDataBytes: 1_000
        )

        await loader.load(url: URL(string: "https://example.com/small.png")!)

        guard case .success = loader.phase else {
            XCTFail("Expected small image to load")
            return
        }
    }

    private func makeSession(data: Data, mimeType: String) -> URLSession {
        MarkdownImageURLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": mimeType,
                    "Content-Length": "\(data.count)"
                ]
            )!
            return (response, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarkdownImageURLProtocolMock.self]
        return URLSession(configuration: configuration)
    }

    private static let onePixelPNGData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )!
}

private final class MarkdownImageURLProtocolMock: URLProtocol {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MarkdownImageURLProtocolMock", code: 0))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
