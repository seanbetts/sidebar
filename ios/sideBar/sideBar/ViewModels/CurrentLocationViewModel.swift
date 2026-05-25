import Combine
import CoreLocation
import Foundation

/// Coordinates live location authorization, updates, and reverse-geocoded labels.
@MainActor public final class CurrentLocationViewModel: ObservableObject {
    /// Latest location authorization status.
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus
    /// Latest live location label, for example "Tignes, France".
    @Published public private(set) var currentLocationLabel: String?
    /// Latest accepted live coordinate.
    @Published public private(set) var currentLocationCoordinate: CLLocationCoordinate2D?
    /// Monotonic revision incremented whenever accepted coordinates change.
    @Published public private(set) var locationRevision: Int = 0

    private let provider: any CurrentLocationProviding
    private let labelResolver: any CurrentLocationLabelResolving
    private let minimumDistanceMeters: CLLocationDistance
    private var cancellables = Set<AnyCancellable>()
    private var lastAcceptedLocation: CLLocation?
    private var resolveLabelTask: Task<Void, Never>?
    private var shouldPromptForAuthorization = false

    public init(
        provider: any CurrentLocationProviding,
        labelResolver: any CurrentLocationLabelResolving,
        minimumDistanceMeters: CLLocationDistance = 500
    ) {
        self.provider = provider
        self.labelResolver = labelResolver
        self.minimumDistanceMeters = minimumDistanceMeters
        self.authorizationStatus = provider.authorizationStatus
        bindProvider()
    }

    deinit {
        resolveLabelTask?.cancel()
    }

    /// Starts location tracking flow.
    public func startTracking() {
        shouldPromptForAuthorization = true
        applyAuthorizationStatus(
            provider.authorizationStatus,
            requestingAuthorizationIfNeeded: true
        )
    }

    /// Starts location tracking only when authorization already exists.
    public func startTrackingIfAuthorized() {
        shouldPromptForAuthorization = false
        applyAuthorizationStatus(
            provider.authorizationStatus,
            requestingAuthorizationIfNeeded: false
        )
    }

    /// Stops location tracking and clears active geocoding work.
    public func stopTracking() {
        provider.stopUpdatingLocation()
        resolveLabelTask?.cancel()
    }

    /// Whether location updates are currently authorized.
    public var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .notDetermined, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func bindProvider() {
        provider.authorizationStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.applyAuthorizationStatus(
                    status,
                    requestingAuthorizationIfNeeded: self.shouldPromptForAuthorization
                )
            }
            .store(in: &cancellables)

        provider.locationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }

    private func applyAuthorizationStatus(
        _ status: CLAuthorizationStatus,
        requestingAuthorizationIfNeeded: Bool = false
    ) {
        authorizationStatus = status
        switch status {
        case .notDetermined:
            provider.stopUpdatingLocation()
            clearCurrentLocation()
            guard requestingAuthorizationIfNeeded else { return }
            shouldPromptForAuthorization = false
            provider.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            shouldPromptForAuthorization = false
            provider.startUpdatingLocation()
        case .denied, .restricted:
            shouldPromptForAuthorization = false
            provider.stopUpdatingLocation()
            clearCurrentLocation()
        @unknown default:
            shouldPromptForAuthorization = false
            provider.stopUpdatingLocation()
        }
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        guard isAuthorized else { return }
        guard shouldAcceptLocation(location) else { return }

        lastAcceptedLocation = location
        currentLocationCoordinate = location.coordinate
        locationRevision += 1
        resolveLocationLabel(for: location)
    }

    private func shouldAcceptLocation(_ location: CLLocation) -> Bool {
        guard let previous = lastAcceptedLocation else {
            return true
        }
        return location.distance(from: previous) >= minimumDistanceMeters
    }

    private func resolveLocationLabel(for location: CLLocation) {
        resolveLabelTask?.cancel()
        resolveLabelTask = Task { [weak self] in
            guard let self else { return }
            let label = await labelResolver.resolveLabel(for: location)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !Task.isCancelled else { return }
            if let label, !label.isEmpty {
                currentLocationLabel = label
            }
        }
    }

    private func clearCurrentLocation() {
        resolveLabelTask?.cancel()
        resolveLabelTask = nil
        lastAcceptedLocation = nil
        currentLocationCoordinate = nil
        currentLocationLabel = nil
    }
}
