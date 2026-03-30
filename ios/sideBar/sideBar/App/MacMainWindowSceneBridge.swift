#if os(macOS)
import SwiftUI

@MainActor
enum MacMainWindowSceneBridge {
    private static var openMainWindowAction: (() -> Void)?

    static func install(openMainWindowAction: @escaping () -> Void) {
        self.openMainWindowAction = openMainWindowAction
    }

    static var isAvailable: Bool {
        openMainWindowAction != nil
    }

    @discardableResult
    static func openMainWindowIfAvailable() -> Bool {
        guard let openMainWindowAction else { return false }
        openMainWindowAction()
        return true
    }
}
#endif
