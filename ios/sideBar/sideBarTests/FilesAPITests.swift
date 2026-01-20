import XCTest
@testable import sideBar

final class FilesAPITests: XCTestCase {
    override func tearDown() {
        FilesURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testDownloadBuildsEncodedPath() async throws {
        let api = FilesAPI(client: makeClient())
        let expected = Data([0x01, 0x02])
        FilesURLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("files/download"))
            XCTAssertTrue(urlString.contains("basePath=docs"))
            XCTAssertTrue(urlString.contains("path=folder%2Ffile.txt"))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expected)
        }

        let data = try await api.download(basePath: "docs", path: "folder/file.txt")

        XCTAssertEqual(data, expected)
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FilesURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class FilesURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = FilesURLProtocolMock.requestHandler else {
            XCTFail("Request handler not set")
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

    override func stopLoading() {
    }
}
