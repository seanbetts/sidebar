import Foundation
import sideBarShared

enum ShareExtensionDiagnostics {
    static let reporter = ExtensionDiagnosticsReporter(
        logger: SystemExtensionDiagnosticsLogger(category: "ShareExtension"),
        store: ExternalSurfaceDiagnosticsStore.shared
    )
}
