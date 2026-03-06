import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class NotesAPITests: XCTestCase {
    override func tearDown() {
        NotesURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testSearchUsesPostAndDecodesItems() async throws {
        let api = NotesAPI(client: makeClient())
        NotesURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("notes/search") == true)
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
                  "name": "Doc",
                  "path": "/doc.md",
                  "type": "file",
                  "size": 1,
                  "modified": 1,
                  "children": null,
                  "expanded": null,
                  "pinned": null,
                  "pinned_order": null,
                  "archived": null,
                  "folder_marker": null
                }
              ]
            }
            """
            return (response, Data(payload.utf8))
        }

        let items = try await api.search(query: "doc", limit: 1)

        XCTAssertEqual(items.first?.name, "Doc")
    }

    func testUpdateNoteSendsSemanticDocumentBody() async throws {
        let api = NotesAPI(client: makeClient())
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([
                    .init(text: "Hello", marks: [.bold]),
                    .init(text: " world", marks: [])
                ])
            ]
        )
        NotesURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(request.url?.absoluteString.contains("notes/note-1") == true)
            let body = try XCTUnwrap(request.httpBodyData())
            let payload = try JSONDecoder().decode(NoteUpdateRequest.self, from: body)
            XCTAssertEqual(payload.document, document)
            XCTAssertEqual(payload.plainText, "Hello world")
            let rawPayload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertNil(rawPayload["content"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let responseBody = """
            {
              "id": "note-1",
              "name": "Hello world",
              "path": "note-1",
              "document": {
                "version": 1,
                "blocks": [
                  {
                    "type": "paragraph",
                    "content": [
                      { "text": "Hello", "marks": ["bold"] },
                      { "text": " world", "marks": [] }
                    ]
                  }
                ]
              },
              "document_version": 1,
              "plain_text": "Hello world",
              "modified": 1,
              "created": 1
            }
            """
            return (response, Data(responseBody.utf8))
        }

        let note = try await api.updateNote(id: "note-1", document: document)

        XCTAssertEqual(note.document, document)
        XCTAssertEqual(note.plainText, "Hello world")
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotesURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class NotesURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = NotesURLProtocolMock.requestHandler else {
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
