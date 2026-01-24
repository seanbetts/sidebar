import Combine
import Foundation
import MapKit

// NOTE: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Loads weather data and formats related state.
public final class WeatherViewModel: LoadableViewModel {
    @Published public private(set) var weather: WeatherResponse?
    @Published public private(set) var locationName: String?

    private let api: any WeatherProviding

    public init(api: any WeatherProviding) {
        self.api = api
    }

    public func load(location: String) async {
        locationName = location
        await withLoading({
            let coordinate = try await searchCoordinates(for: location)
            return try await api.getWeather(lat: coordinate.latitude, lon: coordinate.longitude)
        }, onSuccess: { [weak self] response in
            self?.weather = response
        })
    }

    public func load(lat: Double, lon: Double) async {
        await withLoading({
            try await api.getWeather(lat: lat, lon: lon)
        }, onSuccess: { [weak self] response in
            self?.weather = response
        })
    }

    private func searchCoordinates(for location: String) async throws -> CLLocationCoordinate2D {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = location
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        guard let coordinate = response.mapItems.first?.location.coordinate else {
            throw WeatherLookupError.locationNotFound
        }
        return coordinate
    }
}

private enum WeatherLookupError: LocalizedError {
    case locationNotFound

    var errorDescription: String? {
        switch self {
        case .locationNotFound:
            return "Unable to find that location."
        }
    }
}
