import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class WeatherViewModel: ObservableObject {
    @Published public private(set) var weather: WeatherResponse? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: WeatherAPI

    public init(api: WeatherAPI) {
        self.api = api
    }

    public func load(lat: Double, lon: Double) async {
        errorMessage = nil
        do {
            weather = try await api.getWeather(lat: lat, lon: lon)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
