import Foundation
import os
import CoreSpotlight
#if os(iOS)
import UIKit

@MainActor
final class AppSceneDelegate: NSObject, UIWindowSceneDelegate {
    private let logger = Logger(subsystem: "sideBar", category: "DeepLink")
    private static var queuedDeepLinks: [URL] = []

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard let url = contexts.first?.url else { return }
        guard url.scheme == "sidebar" else { return }
        logger.info("SceneDelegate handling deep link: \(url.absoluteString, privacy: .public)")
        handleOrQueueDeepLink(url)
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
        handleOrQueueDeepLink(url)
    }

    static func flushQueuedDeepLinks(using environment: AppEnvironment) {
        guard !queuedDeepLinks.isEmpty else { return }
        let queued = queuedDeepLinks
        queuedDeepLinks.removeAll()
        for url in queued {
            environment.handleDeepLink(url)
        }
    }

    private func handleOrQueueDeepLink(_ url: URL) {
        guard let environment = AppEnvironment.shared else {
            Self.queuedDeepLinks.append(url)
            logger.info("SceneDelegate queued deep link until environment is ready")
            return
        }
        Self.flushQueuedDeepLinks(using: environment)
        environment.handleDeepLink(url)
    }
}
#endif
