import Foundation
import Combine
import MapKit

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class WeatherViewModel: ObservableObject {
    @Published public private(set) var weather: WeatherResponse? = nil
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var locationName: String? = nil

    private let api: any WeatherProviding

    public init(api: any WeatherProviding) {
        self.api = api
    }

    public func load(location: String) async {
        errorMessage = nil
        isLoading = true
        locationName = location
        do {
            let coordinate = try await searchCoordinates(for: location)
            weather = try await api.getWeather(lat: coordinate.latitude, lon: coordinate.longitude)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func load(lat: Double, lon: Double) async {
        errorMessage = nil
        isLoading = true
        do {
            weather = try await api.getWeather(lat: lat, lon: lon)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
