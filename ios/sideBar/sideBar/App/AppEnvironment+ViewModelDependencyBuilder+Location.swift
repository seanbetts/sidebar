import Foundation

extension AppEnvironment.ViewModelDependencyBuilder {
    static func makeCurrentLocationViewModel(isTestMode: Bool) -> CurrentLocationViewModel {
        CurrentLocationViewModel(
            provider: makeCurrentLocationProvider(isTestMode: isTestMode),
            labelResolver: makeCurrentLocationLabelResolver(isTestMode: isTestMode)
        )
    }

    static func makeCurrentLocationProvider(isTestMode: Bool) -> any CurrentLocationProviding {
        if isTestMode {
            return NoOpCurrentLocationProvider()
        }
        return CoreLocationProvider()
    }

    static func makeCurrentLocationLabelResolver(
        isTestMode: Bool
    ) -> any CurrentLocationLabelResolving {
        if isTestMode {
            return NoOpCurrentLocationLabelResolver()
        }
        return CLGeocoderLocationLabelResolver()
    }
}
