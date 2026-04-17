import Foundation
import sideBarShared

enum SafariExtensionDiagnostics {
    static let reporter = ExtensionDiagnosticsReporter(
        logger: SystemExtensionDiagnosticsLogger(category: "SafariExtension"),
        store: ExternalSurfaceDiagnosticsStore.shared
    )
}
