import Combine
import CoreLocation
import XCTest
@testable import sideBar

@MainActor
final class CurrentLocationViewModelTests: XCTestCase {
    func testStartTrackingRequestsAuthorizationWhenNotDetermined() {
        let provider = MockCurrentLocationProvider(status: .notDetermined)
        let viewModel = CurrentLocationViewModel(
            provider: provider,
            labelResolver: MockCurrentLocationLabelResolver(label: "Tignes, France")
        )

        viewModel.startTracking()

        XCTAssertEqual(provider.requestWhenInUseAuthorizationCallCount, 1)
        XCTAssertEqual(provider.startUpdatingLocationCallCount, 0)
    }

    func testStartTrackingBeginsUpdatesWhenAuthorized() {
        let provider = MockCurrentLocationProvider(status: .authorizedWhenInUse)
        let viewModel = CurrentLocationViewModel(
            provider: provider,
            labelResolver: MockCurrentLocationLabelResolver(label: "Tignes, France")
        )

        viewModel.startTracking()

        XCTAssertEqual(provider.startUpdatingLocationCallCount, 1)
        XCTAssertEqual(provider.requestWhenInUseAuthorizationCallCount, 0)
    }

    func testDeniedAuthorizationClearsCurrentLocation() async {
        let provider = MockCurrentLocationProvider(status: .authorizedWhenInUse)
        let viewModel = CurrentLocationViewModel(
            provider: provider,
            labelResolver: MockCurrentLocationLabelResolver(label: "Tignes, France"),
            minimumDistanceMeters: 0
        )
        let tignes = CLLocation(latitude: 45.4697, longitude: 6.9064)

        viewModel.startTracking()
        provider.emitLocation(tignes)
        await waitForAsyncUpdates()
        XCTAssertEqual(viewModel.currentLocationLabel, "Tignes, France")

        provider.emitAuthorizationStatus(.denied)
        await waitForAsyncUpdates()

        XCTAssertNil(viewModel.currentLocationCoordinate)
        XCTAssertNil(viewModel.currentLocationLabel)
    }

    func testLocationUpdatePublishesCoordinateAndResolvedLabel() async throws {
        let provider = MockCurrentLocationProvider(status: .authorizedWhenInUse)
        let resolver = MockCurrentLocationLabelResolver(label: "Tignes, France")
        let viewModel = CurrentLocationViewModel(
            provider: provider,
            labelResolver: resolver,
            minimumDistanceMeters: 0
        )
        let tignes = CLLocation(latitude: 45.4697, longitude: 6.9064)

        viewModel.startTracking()
        provider.emitLocation(tignes)
        await waitForAsyncUpdates()

        let coordinate = try XCTUnwrap(viewModel.currentLocationCoordinate)
        XCTAssertEqual(coordinate.latitude, 45.4697, accuracy: 0.0001)
        XCTAssertEqual(coordinate.longitude, 6.9064, accuracy: 0.0001)
        XCTAssertEqual(viewModel.currentLocationLabel, "Tignes, France")
        XCTAssertEqual(viewModel.locationRevision, 1)
        XCTAssertEqual(resolver.resolveCallCount, 1)
    }

    func testLocationWithinMinimumDistanceIsIgnored() async {
        let provider = MockCurrentLocationProvider(status: .authorizedWhenInUse)
        let viewModel = CurrentLocationViewModel(
            provider: provider,
            labelResolver: MockCurrentLocationLabelResolver(label: "Tignes, France"),
            minimumDistanceMeters: 200
        )
        let first = CLLocation(latitude: 45.4697, longitude: 6.9064)
        let nearby = CLLocation(latitude: 45.4702, longitude: 6.9066)

        viewModel.startTracking()
        provider.emitLocation(first)
        await waitForAsyncUpdates()
        let revisionAfterFirst = viewModel.locationRevision

        provider.emitLocation(nearby)
        await waitForAsyncUpdates()

        XCTAssertEqual(viewModel.locationRevision, revisionAfterFirst)
    }

    private func waitForAsyncUpdates() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }
}

@MainActor
private final class MockCurrentLocationProvider: CurrentLocationProviding {
    var authorizationStatus: CLAuthorizationStatus
    var isLocationServicesEnabled: Bool

    private let authorizationSubject = PassthroughSubject<CLAuthorizationStatus, Never>()
    private let locationSubject = PassthroughSubject<CLLocation, Never>()

    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        authorizationSubject.eraseToAnyPublisher()
    }

    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    private(set) var requestWhenInUseAuthorizationCallCount = 0
    private(set) var startUpdatingLocationCallCount = 0
    private(set) var stopUpdatingLocationCallCount = 0

    init(
        status: CLAuthorizationStatus,
        isLocationServicesEnabled: Bool = true
    ) {
        self.authorizationStatus = status
        self.isLocationServicesEnabled = isLocationServicesEnabled
    }

    func requestWhenInUseAuthorization() {
        requestWhenInUseAuthorizationCallCount += 1
    }

    func startUpdatingLocation() {
        startUpdatingLocationCallCount += 1
    }

    func stopUpdatingLocation() {
        stopUpdatingLocationCallCount += 1
    }

    func emitAuthorizationStatus(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        authorizationSubject.send(status)
    }

    func emitLocation(_ location: CLLocation) {
        locationSubject.send(location)
    }
}

private final class MockCurrentLocationLabelResolver: CurrentLocationLabelResolving {
    let label: String?
    private(set) var resolveCallCount = 0

    init(label: String?) {
        self.label = label
    }

    func resolveLabel(for location: CLLocation) async -> String? {
        _ = location
        resolveCallCount += 1
        return label
    }
}
