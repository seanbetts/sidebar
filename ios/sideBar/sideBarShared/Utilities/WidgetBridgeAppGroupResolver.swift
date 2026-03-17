import Foundation

public struct WidgetBridgeAppGroupResolution: Equatable {
    public let id: String?
    public let source: String

    public init(id: String?, source: String) {
        self.id = id
        self.source = source
    }
}

public enum WidgetBridgeAppGroupResolver {
    public static func resolve(
        configuredValue: String?,
        bundleIdentifier: String?
    ) -> WidgetBridgeAppGroupResolution {
        if let configured = AppGroupConfiguration.resolvedAppGroupId(
            configuredValue: configuredValue,
            bundleIdentifier: nil
        ) {
            return WidgetBridgeAppGroupResolution(id: configured, source: "info_plist")
        }

        if let derived = AppGroupConfiguration.resolvedAppGroupId(
            configuredValue: nil,
            bundleIdentifier: bundleIdentifier
        ) {
            return WidgetBridgeAppGroupResolution(id: derived, source: "bundle_identifier")
        }

        return WidgetBridgeAppGroupResolution(id: nil, source: "unavailable")
    }
}
