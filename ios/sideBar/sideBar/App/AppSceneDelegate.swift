import Foundation
import os
#if os(iOS)
import UIKit

final class AppSceneDelegate: NSObject, UIWindowSceneDelegate {
    private let logger = Logger(subsystem: "sideBar", category: "DeepLink")

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard let url = contexts.first?.url else { return }
        guard url.scheme == "sidebar" else { return }
        logger.info("SceneDelegate handling deep link: \(url.absoluteString, privacy: .public)")
        if let environment = AppEnvironment.shared {
            Task { @MainActor in
                environment.handleDeepLink(url)
            }
            return
        }
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let environment = AppEnvironment.shared {
                    environment.handleDeepLink(url)
                    return
                }
            }
            logger.error("SceneDelegate dropped deep link (environment not ready)")
        }
    }
}
#endif
