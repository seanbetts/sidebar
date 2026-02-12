import Foundation
import XCTest
import SafariServices
import sideBarShared
@testable import sideBar_Safari_Extension
@testable import ShareExtension

final class SafariExtensionCoverageTests: XCTestCase {
    private let suiteName = "SafariExtensionCoverageTests"

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    private final class CapturingExtensionContext: NSExtensionContext {
        var suppliedInputItems: [Any] = []
        var completedItems: [Any]?
        var onComplete: (() -> Void)?

        override var inputItems: [Any] {
            suppliedInputItems
        }

        override func completeRequest(
            returningItems items: [Any]?,
            completionHandler: ((Bool) -> Void)? = nil
        ) {
            completedItems = items
            onComplete?()
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
        let completed = expectation(description: "Safari extension completes request")
        context.onComplete = {
            completed.fulfill()
        }

        SafariWebExtensionHandler().beginRequest(with: context)
        wait(for: [completed], timeout: 2.0)

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

    func testSafariSaveErrorMessagesMatchShareExtensionMapper() async {
        let url = "https://example.com/article"
        let scenarios: [(error: Error, expectedCode: ExtensionMessageCode)] = [
            (APIClientError.requestFailed(401), .notAuthenticated),
            (APIClientError.requestFailed(408), .networkError),
            (APIClientError.apiError("Unable to save website"), .uploadFailed)
        ]

        for scenario in scenarios {
            let store = makeStore()
            let message: [String: Any] = [
                "action": "save_url",
                "url": url
            ]

            let payload = await SafariExtensionMessageHandler.responsePayload(
                for: message,
                pendingStore: store,
                saveWebsite: { _ in
                    throw scenario.error
                }
            )

            XCTAssertEqual(payload["ok"] as? Bool, false)
            XCTAssertEqual(payload["code"] as? String, scenario.expectedCode.rawValue)
            XCTAssertEqual(
                payload["error"] as? String,
                ShareExtensionMessageMapper.errorMessage(for: scenario.error)
            )
            XCTAssertTrue(store.loadAll().isEmpty)
        }
    }

    private func makeStore() -> PendingShareStore {
        let defaults = UserDefaults(suiteName: suiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
    }
}
