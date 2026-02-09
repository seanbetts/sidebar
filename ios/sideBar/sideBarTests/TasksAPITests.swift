import XCTest
import sideBarShared
@testable import sideBar

final class TasksAPITests: XCTestCase {
    private static let protocolIsolationLock = NSLock()

    override func setUp() {
        super.setUp()
        Self.protocolIsolationLock.lock()
    }

    override func tearDown() {
        TasksURLProtocolMock.requestHandler = nil
        Self.protocolIsolationLock.unlock()
        super.tearDown()
    }

    // MARK: - GET endpoints

    func testListDecodesResponse() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/lists/today") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {
              "scope": "today",
              "generated_at": "2025-01-01",
              "tasks": [{"id":"t1","title":"Buy milk","status":"open"}],
              "projects": [],
              "groups": []
            }
            """
            return (response, Data(payload.utf8))
        }

        let result = try await api.list(scope: "today")

        XCTAssertEqual(result.scope, "today")
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.tasks[0].id, "t1")
    }

    func testProjectTasksUsesCorrectPath() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/projects/p1/tasks") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"scope":"project","generated_at":null,"tasks":[],"projects":[],"groups":[]}
            """
            return (response, Data(payload.utf8))
        }

        let result = try await api.projectTasks(projectId: "p1")
        XCTAssertEqual(result.scope, "project")
    }

    func testGroupTasksUsesCorrectPath() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/groups/g1/tasks") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"scope":"group","generated_at":null,"tasks":[],"projects":[],"groups":[]}
            """
            return (response, Data(payload.utf8))
        }

        let result = try await api.groupTasks(groupId: "g1")
        XCTAssertEqual(result.scope, "group")
    }

    func testSearchEncodesQueryParameter() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("tasks/search"))
            XCTAssertTrue(urlString.contains("query=hello%20world") || urlString.contains("query=hello+world"))
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"scope":"search","generated_at":null,"tasks":[],"projects":null,"groups":null}
            """
            return (response, Data(payload.utf8))
        }

        let result = try await api.search(query: "hello world")
        XCTAssertEqual(result.scope, "search")
    }

    func testCountsDecodesResponse() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/counts") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {
              "generated_at": null,
              "counts": {"inbox":3,"today":5,"upcoming":10,"completed":20},
              "projects": [{"id":"p1","count":2}],
              "groups": [{"id":"g1","count":4}]
            }
            """
            return (response, Data(payload.utf8))
        }

        let result = try await api.counts()

        XCTAssertEqual(result.counts.inbox, 3)
        XCTAssertEqual(result.counts.today, 5)
        XCTAssertEqual(result.counts.upcoming, 10)
        XCTAssertEqual(result.counts.completed, 20)
        XCTAssertEqual(result.projects.first?.id, "p1")
        XCTAssertEqual(result.groups.first?.count, 4)
    }

    // MARK: - POST endpoints

    func testCreateGroupPostsTitle() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/groups") == true)
            let body = request.httpBodyData().flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            XCTAssertEqual(body?["title"] as? String, "Work")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"id":"g1","title":"Work","updated_at":null}
            """
            return (response, Data(payload.utf8))
        }

        let group = try await api.createGroup(title: "Work")
        XCTAssertEqual(group.id, "g1")
        XCTAssertEqual(group.title, "Work")
    }

    func testCreateProjectPostsTitleAndGroupId() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/projects") == true)
            let body = request.httpBodyData().flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            XCTAssertEqual(body?["title"] as? String, "Alpha")
            XCTAssertEqual(body?["groupId"] as? String, "g1")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"id":"p1","title":"Alpha","groupId":"g1","status":"active","updated_at":null}
            """
            return (response, Data(payload.utf8))
        }

        let project = try await api.createProject(title: "Alpha", groupId: "g1")
        XCTAssertEqual(project.id, "p1")
        XCTAssertEqual(project.groupId, "g1")
    }

    func testApplyPostsOperationBatch() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/apply") == true)
            let body = request.httpBodyData().flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            let operations = body?["operations"] as? [[String: Any]]
            XCTAssertEqual(operations?.count, 1)
            // Verify snake_case encoding
            XCTAssertEqual(operations?.first?["operation_id"] as? String, "op-1")
            XCTAssertEqual(operations?.first?["due_date"] as? String, "2025-03-15")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"applied":["op-1"],"tasks":[],"nextTasks":[],"conflicts":[],"updates":null,"serverUpdatedSince":null}
            """
            return (response, Data(payload.utf8))
        }

        let operation = TaskOperationPayload(
            operationId: "op-1",
            op: "add",
            title: "New task",
            dueDate: "2025-03-15"
        )
        let result = try await api.apply(TaskOperationBatch(operations: [operation]))
        XCTAssertEqual(result.applied, ["op-1"])
    }

    func testSyncPostsLastSyncAndOperations() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/sync") == true)
            let body = request.httpBodyData().flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            XCTAssertEqual(body?["last_sync"] as? String, "2025-01-01T00:00:00Z")
            let operations = body?["operations"] as? [[String: Any]]
            XCTAssertEqual(operations?.count, 1)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"applied":["op-1"],"tasks":[],"nextTasks":[],"conflicts":[],"updates":null,"serverUpdatedSince":"2025-01-02T00:00:00Z"}
            """
            return (response, Data(payload.utf8))
        }

        let operation = TaskOperationPayload(operationId: "op-1", op: "complete", id: "t1")
        let result = try await api.sync(TaskSyncRequest(
            lastSync: "2025-01-01T00:00:00Z",
            operations: [operation]
        ))
        XCTAssertEqual(result.applied, ["op-1"])
        XCTAssertEqual(result.serverUpdatedSince, "2025-01-02T00:00:00Z")
    }

    // MARK: - PATCH endpoints

    func testRenameGroupPatchesTitle() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/groups/g1") == true)
            let body = request.httpBodyData().flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            XCTAssertEqual(body?["title"] as? String, "Personal")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"id":"g1","title":"Personal","updated_at":null}
            """
            return (response, Data(payload.utf8))
        }

        let group = try await api.renameGroup(groupId: "g1", title: "Personal")
        XCTAssertEqual(group.title, "Personal")
    }

    func testRenameProjectPatchesTitle() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/projects/p1") == true)
            let body = request.httpBodyData().flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            XCTAssertEqual(body?["title"] as? String, "Beta")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {"id":"p1","title":"Beta","groupId":"g1","status":"active","updated_at":null}
            """
            return (response, Data(payload.utf8))
        }

        let project = try await api.renameProject(projectId: "p1", title: "Beta")
        XCTAssertEqual(project.title, "Beta")
    }

    // MARK: - DELETE endpoints

    func testDeleteGroupUsesDelete() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/groups/g1") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        try await api.deleteGroup(groupId: "g1")
    }

    func testDeleteProjectUsesDelete() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("tasks/projects/p1") == true)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        try await api.deleteProject(projectId: "p1")
    }

    // MARK: - Error handling

    func testApplyDecodesConflictsInSyncResponse() async throws {
        let api = TasksAPI(client: makeClient())
        TasksURLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let payload = """
            {
              "applied": [],
              "tasks": [],
              "nextTasks": [],
              "conflicts": [{
                "operationId": "op-1",
                "op": "complete",
                "id": "t1",
                "clientUpdatedAt": "2025-01-01",
                "serverUpdatedAt": "2025-01-02",
                "serverTask": {"id":"t1","title":"Changed","status":"open"}
              }],
              "updates": null,
              "serverUpdatedSince": null
            }
            """
            return (response, Data(payload.utf8))
        }

        let operation = TaskOperationPayload(operationId: "op-1", op: "complete", id: "t1")
        let result = try await api.apply(TaskOperationBatch(operations: [operation]))
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts[0].operationId, "op-1")
        XCTAssertEqual(result.conflicts[0].serverTask.title, "Changed")
    }

    // MARK: - Helpers

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TasksURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class TasksURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = TasksURLProtocolMock.requestHandler else {
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
