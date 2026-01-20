import XCTest
@testable import sideBar

private typealias URLProtocolMock = SettingsURLProtocolMock

final class SettingsAPITests: XCTestCase {
    override func tearDown() {
        SettingsURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testGetSettingsDecodesResponse() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "user_id": "u1",
              "communication_style": "friendly",
              "working_relationship": null,
              "name": "User",
              "job_title": null,
              "employer": null,
              "date_of_birth": null,
              "gender": null,
              "pronouns": null,
              "location": null,
              "profile_image_url": null,
              "enabled_skills": []
            }
            """
            return (response, Data(payload.utf8))
        }

        let settings = try await api.getSettings()

        XCTAssertEqual(settings.userId, "u1")
        XCTAssertEqual(settings.communicationStyle, "friendly")
    }

    func testRotateShortcutsTokenUsesPost() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("settings/shortcuts/pat/rotate") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"token\":\"abc\"}".utf8))
        }

        let response = try await api.rotateShortcutsToken()

        XCTAssertEqual(response.token, "abc")
    }

    func testGetProfileImageUsesRequestData() async throws {
        let api = SettingsAPI(client: makeClient())
        let expected = Data([0x01, 0x02])
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expected)
        }

        let data = try await api.getProfileImage()

        XCTAssertEqual(data, expected)
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class SettingsURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = SettingsURLProtocolMock.requestHandler else {
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
