import Combine
import CoreLocation
import Foundation
import MapKit

/// Abstraction for location authorization and coordinate updates.
public protocol CurrentLocationProviding: AnyObject {
    /// Current authorization status for location access.
    var authorizationStatus: CLAuthorizationStatus { get }
    /// Publisher for authorization status changes.
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> { get }
    /// Publisher for location updates.
    var locationPublisher: AnyPublisher<CLLocation, Never> { get }

    /// Requests foreground location permission.
    func requestWhenInUseAuthorization()
    /// Starts receiving location updates.
    func startUpdatingLocation()
    /// Stops receiving location updates.
    func stopUpdatingLocation()
}

@MainActor
/// CoreLocation-backed location provider.
public final class CoreLocationProvider: NSObject, CurrentLocationProviding {
    private let manager: CLLocationManager
    private let authorizationStatusSubject: CurrentValueSubject<CLAuthorizationStatus, Never>
    private let locationSubject = PassthroughSubject<CLLocation, Never>()

    public var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    public var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        authorizationStatusSubject.eraseToAnyPublisher()
    }

    public var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    public init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        self.authorizationStatusSubject = CurrentValueSubject(manager.authorizationStatus)
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
        self.manager.distanceFilter = 250
    }

    public func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    public func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    public func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatusSubject.send(manager.authorizationStatus)
    }

    public func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        authorizationStatusSubject.send(status)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        locationSubject.send(latest)
    }
}

/// Resolves a human-friendly location label from coordinates.
public protocol CurrentLocationLabelResolving {
    /// Returns a location label like "Tignes, France" for a coordinate.
    func resolveLabel(for location: CLLocation) async -> String?
}

/// MapKit-backed location label resolver.
public final class CLGeocoderLocationLabelResolver: CurrentLocationLabelResolving {
    public init() {
    }

    public func resolveLabel(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return nil
        }
        do {
            let mapItems = try await request.mapItems
            guard let mapItem = mapItems.first else {
                return nil
            }
            let city = mapItem.addressRepresentations?.cityName
            let region = mapItem.addressRepresentations?.regionName
            if let city, let region {
                return "\(city), \(region)"
            }
            if let city {
                return city
            }
            if let region {
                return region
            }
            return mapItem.address?.shortAddress ?? mapItem.address?.fullAddress
        } catch {
            return nil
        }
    }
}
