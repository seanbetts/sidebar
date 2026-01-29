import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class WeatherViewModelTests: XCTestCase {
    func testLoadWeatherSetsResponse() async {
        let response = WeatherResponse(
            temperatureC: 18,
            feelsLikeC: 17,
            weatherCode: 1,
            isDay: 1,
            windSpeedKph: 5,
            windDirectionDegrees: 120,
            precipitationMm: 0,
            cloudCoverPercent: 20,
            daily: [],
            fetchedAt: 0
        )
        let viewModel = WeatherViewModel(api: MockWeatherAPI(result: .success(response)))

        await viewModel.load(lat: 1, lon: 2)

        XCTAssertEqual(viewModel.weather?.temperatureC, 18)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadWeatherSetsError() async {
        let viewModel = WeatherViewModel(api: MockWeatherAPI(result: .failure(MockError.forced)))

        await viewModel.load(lat: 1, lon: 2)

        XCTAssertNotNil(viewModel.errorMessage)
    }
}

private enum MockError: Error {
    case forced
}

private struct MockWeatherAPI: WeatherProviding {
    let result: Result<WeatherResponse, Error>

    func getWeather(lat: Double, lon: Double) async throws -> WeatherResponse {
        _ = lat
        _ = lon
        return try result.get()
    }
}
