//
//  SafariWebExtensionHandler.swift
//  sideBar Safari Extension
//
//  Created by Sean Betts on 01/02/2026.
//

import SafariServices
import AppIntents
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

        let responsePayload = SafariExtensionMessageHandler.responsePayload(
            for: message,
            pendingStore: .shared
        )
        os_log(.default, "SafariWebExtensionHandler response=%@", String(describing: responsePayload))

        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [ SFExtensionMessageKey: responsePayload ]
        } else {
            response.userInfo = [ "message": responsePayload ]
        }

        context.completeRequest(returningItems: [ response ], completionHandler: nil)
    }
}
