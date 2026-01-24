import Foundation
import XCTest
@testable import sideBar

@MainActor
final class PlacesViewModelTests: XCTestCase {
    override func tearDown() {
        PlacesURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testAutocompleteSetsPredictions() async {
        let client = makeClient()
        let api = PlacesAPI(client: client)
        let viewModel = PlacesViewModel(api: api)
        PlacesURLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let json = "{\"predictions\":[{\"description\":\"Paris\",\"place_id\":\"p1\"}]}"
            return (response, Data(json.utf8))
        }

        await viewModel.autocomplete(query: "Par")

        XCTAssertEqual(viewModel.predictions.first?.description, "Paris")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testReverseSetsLabel() async {
        let client = makeClient()
        let api = PlacesAPI(client: client)
        let viewModel = PlacesViewModel(api: api)
        PlacesURLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let json = "{\"label\":\"London\"}"
            return (response, Data(json.utf8))
        }

        await viewModel.reverse(lat: 51.5, lon: -0.1)

        XCTAssertEqual(viewModel.reverseLabel, "London")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAutocompleteSetsErrorOnFailure() async {
        let client = makeClient()
        let api = PlacesAPI(client: client)
        let viewModel = PlacesViewModel(api: api)
        PlacesURLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        await viewModel.autocomplete(query: "Par")

        XCTAssertNotNil(viewModel.errorMessage)
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlacesURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class PlacesURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = PlacesURLProtocolMock.requestHandler else {
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
