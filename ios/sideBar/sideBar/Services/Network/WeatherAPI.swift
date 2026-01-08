import Foundation

public struct WeatherAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func getWeather(lat: Double, lon: Double) async throws -> WeatherResponse {
        let path = "weather?lat=\(lat)&lon=\(lon)"
        return try await client.request(path)
    }
}
