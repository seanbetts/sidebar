import Foundation
import os
import CoreSpotlight
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

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == CSSearchableItemActionType else { return }
        guard let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            logger.error("SceneDelegate: Missing Spotlight identifier")
            return
        }
        guard let url = SpotlightIndexer.deepLinkURL(from: identifier) else {
            logger.error("SceneDelegate: Invalid Spotlight identifier: \(identifier, privacy: .public)")
            return
        }
        logger.info("SceneDelegate handling Spotlight tap: \(identifier, privacy: .public)")
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
            logger.error("SceneDelegate dropped Spotlight deep link (environment not ready)")
        }
    }
}
#endif
