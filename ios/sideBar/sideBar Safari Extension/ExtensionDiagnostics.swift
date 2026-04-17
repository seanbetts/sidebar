import Foundation
import sideBarShared

enum SafariExtensionDiagnostics {
    static let reporter = ExtensionDiagnosticsReporter(
        logger: SystemExtensionDiagnosticsLogger(category: "SafariExtension"),
        store: ExternalSurfaceDiagnosticsStore.shared
    )

    static func ensureSentryStarted() {
        // The vendored Sentry xcframework is static, so linking it into each embedded
        // extension duplicates Objective-C classes inside the host app process.
    }
}
