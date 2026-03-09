//
//  SafariWebExtensionHandler.swift
//  sideBar Safari Extension (macOS) Extension
//
//  Created by Sean Betts on 01/02/2026.
//

import SafariServices
import os.log
import sideBarShared

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(
            .default,
            "Received message from browser.runtime.sendNativeMessage: %@ (profile: %@)",
            String(describing: message),
            profile?.uuidString ?? "none"
        )
        let payload = message as? [String: Any]
        let action = payload?["action"] as? String
        let urlString = payload?["url"] as? String
        ExternalSurfaceDiagnosticsStore.shared.record(
            surface: "safari_extension",
            stage: "begin_request",
            message: "Received Safari extension request.",
            metadata: [
                "action": action ?? "nil",
                "url": urlString ?? "nil",
                "profile": profile?.uuidString ?? "none",
                "bundle_id": Bundle.main.bundleIdentifier ?? "nil"
            ]
        )

        Task {
            let responsePayload = await SafariExtensionMessageHandler.responsePayload(
                for: message,
                pendingStore: .shared,
                refreshAccessToken: {
                    await SafariExtensionAuthCoordinator.forceRefreshAccessToken()
                }
            )
            os_log(.default, "SafariWebExtensionHandler response=%@", String(describing: responsePayload))
            ExternalSurfaceDiagnosticsStore.shared.record(
                surface: "safari_extension",
                stage: "complete_request",
                message: "Completed Safari extension request.",
                metadata: [
                    "action": action ?? "nil",
                    "url": urlString ?? "nil",
                    "ok": (responsePayload["ok"] as? Bool).map { $0 ? "true" : "false" } ?? "nil",
                    "code": responsePayload["code"] as? String ?? "nil",
                    "bundle_id": Bundle.main.bundleIdentifier ?? "nil"
                ]
            )

            let response = NSExtensionItem()
            if #available(iOS 15.0, macOS 11.0, *) {
                response.userInfo = [ SFExtensionMessageKey: responsePayload ]
            } else {
                response.userInfo = [ "message": responsePayload ]
            }

            context.completeRequest(returningItems: [ response ], completionHandler: nil)
        }
    }
}
