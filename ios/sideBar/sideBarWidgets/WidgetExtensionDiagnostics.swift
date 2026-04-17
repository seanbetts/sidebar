import Foundation
import sideBarShared

enum WidgetExtensionDiagnostics {
    static let reporter = ExtensionDiagnosticsReporter(
        logger: SystemExtensionDiagnosticsLogger(category: "WidgetExtension"),
        store: ExternalSurfaceDiagnosticsStore.shared
    )
}
