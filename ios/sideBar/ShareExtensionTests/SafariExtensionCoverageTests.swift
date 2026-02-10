import Foundation
import XCTest
import SafariServices
@testable import sideBar_Safari_Extension

final class SafariExtensionCoverageTests: XCTestCase {
    private final class CapturingExtensionContext: NSExtensionContext {
        var suppliedInputItems: [Any] = []
        var completedItems: [Any]?

        override var inputItems: [Any] {
            suppliedInputItems
        }

        override func completeRequest(
            returningItems items: [Any]?,
            completionHandler: ((Bool) -> Void)? = nil
        ) {
            completedItems = items
            completionHandler?(true)
        }
    }

    func testBeginRequestReturnsUnsupportedActionForUnknownPayload() {
        let context = CapturingExtensionContext()
        let request = NSExtensionItem()
        if #available(iOS 15.0, *) {
            request.userInfo = [
                SFExtensionMessageKey: [
                    "action": "unknown_action",
                    "url": "https://example.com"
                ]
            ]
        } else {
            request.userInfo = [
                "message": [
                    "action": "unknown_action",
                    "url": "https://example.com"
                ]
            ]
        }
        context.suppliedInputItems = [request]

        SafariWebExtensionHandler().beginRequest(with: context)

        let responseItem = context.completedItems?.first as? NSExtensionItem
        XCTAssertNotNil(responseItem)

        let payloadKey: String
        if #available(iOS 15.0, *) {
            payloadKey = SFExtensionMessageKey
        } else {
            payloadKey = "message"
        }
        let payload = responseItem?.userInfo?[payloadKey] as? [String: Any]
        XCTAssertEqual(payload?["ok"] as? Bool, false)
        XCTAssertEqual(payload?["code"] as? String, "unsupported_action")
        XCTAssertEqual(payload?["error"] as? String, "This action is not supported.")
    }
}
