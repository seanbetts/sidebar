import Foundation
import os.log

extension PendingShareStore {
    func logMissingAppGroupIfNeeded(context: String) {
        guard defaults == nil || rootDirectory == nil else { return }
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let groupId = AppGroupConfiguration.appGroupId ?? "unset"
        os_log(
            .error,
            log: Self.log,
            "App group unavailable (%{public}@). bundleId=%{public}@ appGroupId=%{public}@",
            context,
            bundleId,
            groupId
        )
        recordDiagnostics(
            stage: "missing_app_group",
            message: "App group storage was unavailable.",
            metadata: [
                "context": context,
                "bundle_id": bundleId,
                "app_group_id": groupId
            ]
        )
    }

    func hasRequiredStorage(needsFileContainer: Bool, context: String) -> Bool {
        let hasDefaults = defaults != nil
        let hasRootDirectory = rootDirectory != nil
        if hasDefaults && (!needsFileContainer || hasRootDirectory) {
            recordDiagnostics(
                stage: "storage_available",
                message: "Shared storage is available for pending shares.",
                metadata: [
                    "context": context,
                    "has_defaults": hasDefaults ? "true" : "false",
                    "has_root_directory": hasRootDirectory ? "true" : "false",
                    "needs_file_container": needsFileContainer ? "true" : "false"
                ]
            )
            return true
        }
        logMissingAppGroupIfNeeded(context: context)
        return false
    }

    func recordDiagnostics(
        stage: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "pending_share_store",
            stage: stage,
            message: message,
            metadata: metadata.merging(
                [
                    "bundle_id": Bundle.main.bundleIdentifier ?? "nil",
                    "app_group_id": AppGroupConfiguration.appGroupId ?? "nil"
                ],
                uniquingKeysWith: { current, _ in current }
            )
        )
    }
}
