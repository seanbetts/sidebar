import Combine
import CoreLocation
import Foundation

/// Abstraction for location authorization and coordinate updates.
public protocol CurrentLocationProviding: AnyObject {
    /// Current authorization status for location access.
    var authorizationStatus: CLAuthorizationStatus { get }
    /// Whether location services are enabled on this device.
    var isLocationServicesEnabled: Bool { get }
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

    public var isLocationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
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

/// CLGeocoder-backed location label resolver.
public final class CLGeocoderLocationLabelResolver: CurrentLocationLabelResolving {
    private let geocoder: CLGeocoder

    public init(geocoder: CLGeocoder = CLGeocoder()) {
        self.geocoder = geocoder
    }

    public func resolveLabel(for location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                return nil
            }
            let locality = placemark.locality
                ?? placemark.subAdministrativeArea
                ?? placemark.administrativeArea
            let country = placemark.country ?? placemark.isoCountryCode
            if let locality, let country {
                return "\(locality), \(country)"
            }
            return locality ?? country
        } catch {
            return nil
        }
    }
}
