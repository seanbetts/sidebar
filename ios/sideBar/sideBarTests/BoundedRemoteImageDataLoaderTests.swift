import XCTest
@testable import sideBar

final class BoundedRemoteImageDataLoaderTests: XCTestCase {
    override func tearDown() {
        BoundedRemoteImageURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testLoaderRejectsOversizedImageDownloads() async throws {
        let data = Data(repeating: 0xA, count: 5)
        let loaded = try await BoundedRemoteImageDataLoader.load(
            url: URL(string: "https://example.com/large.png")!,
            session: makeSession(data: data, mimeType: "image/png"),
            maxBytes: 4
        )

        XCTAssertNil(loaded)
    }

    func testLoaderRejectsNonImageResponses() async throws {
        let loaded = try await BoundedRemoteImageDataLoader.load(
            url: URL(string: "https://example.com/page")!,
            session: makeSession(data: Data("not image".utf8), mimeType: "text/html"),
            maxBytes: 1_000
        )

        XCTAssertNil(loaded)
    }

    func testLoaderLoadsSmallImageDownloads() async throws {
        let payload = Data([0x1, 0x2, 0x3])
        let loaded = try await BoundedRemoteImageDataLoader.load(
            url: URL(string: "https://example.com/small.png")!,
            session: makeSession(data: payload, mimeType: "image/png"),
            maxBytes: 1_000
        )

        XCTAssertEqual(loaded, payload)
    }

    private func makeSession(data: Data, mimeType: String) -> URLSession {
        BoundedRemoteImageURLProtocolMock.requestHandler = { request in
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
        configuration.protocolClasses = [BoundedRemoteImageURLProtocolMock.self]
        return URLSession(configuration: configuration)
    }
}

private final class BoundedRemoteImageURLProtocolMock: URLProtocol {
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "BoundedRemoteImageURLProtocolMock", code: 0))
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
