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
        SafariExtensionDiagnostics.ensureSentryStarted()
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
        SafariExtensionDiagnostics.reporter.recordBreadcrumb(
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
            let responsePayload = await ExtensionURLMessageHandler.handleSaveURLMessage(
                action: action,
                urlString: urlString,
                pendingStore: .shared,
                saveStrategy: .queueOnly
            )
            os_log(.default, "SafariWebExtensionHandler response=%@", String(describing: responsePayload))
            let responseMetadata = [
                "action": action ?? "nil",
                "url": urlString ?? "nil",
                "ok": (responsePayload["ok"] as? Bool).map { $0 ? "true" : "false" } ?? "nil",
                "code": responsePayload["code"] as? String ?? "nil",
                "bundle_id": Bundle.main.bundleIdentifier ?? "nil"
            ]
            if responsePayload["ok"] as? Bool == false {
                SafariExtensionDiagnostics.reporter.captureFailure(
                    surface: "safari_extension",
                    stage: "complete_request",
                    message: "Safari extension request failed.",
                    metadata: responseMetadata
                )
            } else {
                SafariExtensionDiagnostics.reporter.recordBreadcrumb(
                    surface: "safari_extension",
                    stage: "complete_request",
                    message: "Completed Safari extension request.",
                    metadata: responseMetadata
                )
            }

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
