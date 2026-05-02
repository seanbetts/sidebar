import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WebsitesAPITests: XCTestCase {
    private var router: ScopedURLProtocolRouter!

    override func setUp() {
        super.setUp()
        router = ScopedURLProtocolRouter()
    }

    override func tearDown() {
        router.invalidate()
        router = nil
        super.tearDown()
    }

    func testSaveUsesPostAndDecodesQueuedJobResponse() async throws {
        let api = WebsitesAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("websites/save") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 202,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "job_id": "job-1",
              "status": "queued"
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.save(url: "https://example.com")

        XCTAssertEqual(response.jobId, "job-1")
        XCTAssertEqual(response.status, "queued")
    }

    func testJobStatusDecodesCompletedWebsiteResponse() async throws {
        let api = WebsitesAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("websites/jobs/job-1") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "job_id": "job-1",
              "status": "completed",
              "website": {
                "id": "w1",
                "title": "Site",
                "url": "https://example.com",
                "url_full": "https://example.com/full",
                "domain": "example.com",
                "content": "Body",
                "source": "web",
                "pinned": false,
                "archived": false
              }
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.jobStatus(id: "job-1")

        XCTAssertEqual(response.jobId, "job-1")
        XCTAssertEqual(response.status, "completed")
        XCTAssertEqual(response.website?.id, "w1")
        XCTAssertEqual(response.website?.content, "Body")
    }

    func testCancelUsesPostRequest() async throws {
        let api = WebsitesAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("websites/jobs/job-1/cancel") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        try await api.cancel(jobId: "job-1")
    }

    func testListDecodesReadingTimeField() async throws {
        let api = WebsitesAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("websites") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "items": [
                {
                  "id": "w1",
                  "title": "Site",
                  "url": "https://example.com",
                  "domain": "example.com",
                  "pinned": false,
                  "archived": false,
                  "reading_time": "12 mins"
                }
              ]
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.list()

        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items.first?.readingTime, "12 mins")
    }

    func testGetDecodesReadingTimeField() async throws {
        let api = WebsitesAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("websites/w1") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "id": "w1",
              "title": "Site",
              "url": "https://example.com",
              "domain": "example.com",
              "content": "Body",
              "pinned": false,
              "archived": false,
              "reading_time": "8 mins"
            }
            """
            return (response, Data(payload.utf8))
        }

        let detail = try await api.get(id: "w1")

        XCTAssertEqual(detail.id, "w1")
        XCTAssertEqual(detail.readingTime, "8 mins")
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: router.baseURL,
            accessTokenProvider: { "token-123" }
        )
        let session = router.makeSession()
        return APIClient(config: config, session: session)
    }
}
