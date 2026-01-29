import XCTest
import sideBarShared
@testable import sideBar

final class WeatherAPITests: XCTestCase {
    override func tearDown() {
        WeatherURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testGetWeatherBuildsQueryAndDecodes() async throws {
        let client = makeClient()
        let api = WeatherAPI(client: client)
        WeatherURLProtocolMock.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("weather?lat=1.23&lon=4.56") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "temperature_c": 18,
              "feels_like_c": 17,
              "weather_code": 1,
              "is_day": 1,
              "wind_speed_kph": 5,
              "wind_direction_degrees": 120,
              "precipitation_mm": 0,
              "cloud_cover_percent": 20,
              "daily": [],
              "fetched_at": 0
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.getWeather(lat: 1.23, lon: 4.56)

        XCTAssertEqual(response.temperatureC, 18)
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeatherURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class WeatherURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = WeatherURLProtocolMock.requestHandler else {
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
