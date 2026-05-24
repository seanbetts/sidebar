import Foundation
import XCTest
import SafariServices
import sideBarShared
@testable import sideBar_Safari_Extension
@testable import ShareExtension

final class SafariExtensionCoverageTests: XCTestCase {
    private let suiteName = "SafariExtensionCoverageTests"
    private var temporaryBundles: [URL] = []
    private var temporarySuiteNames: [String] = []

    override func tearDown() {
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
        }
        for temporarySuiteName in temporarySuiteNames {
            if let defaults = UserDefaults(suiteName: temporarySuiteName) {
                defaults.removePersistentDomain(forName: temporarySuiteName)
            }
        }
        temporarySuiteNames.removeAll()
        for bundleURL in temporaryBundles {
            try? FileManager.default.removeItem(at: bundleURL)
        }
        temporaryBundles.removeAll()
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

    func testBeginRequestRecordsSharedDiagnosticsAtEntry() {
        ExternalSurfaceDiagnosticsStore.shared.clear()
        defer { ExternalSurfaceDiagnosticsStore.shared.clear() }

        let context = CapturingExtensionContext()
        let request = NSExtensionItem()
        if #available(iOS 15.0, *) {
            request.userInfo = [
                SFExtensionMessageKey: [
                    "action": "save_url",
                    "url": "https://example.com/private/path?token=secret#fragment"
                ]
            ]
        } else {
            request.userInfo = [
                "message": [
                    "action": "save_url",
                    "url": "https://example.com/private/path?token=secret#fragment"
                ]
            ]
        }
        context.suppliedInputItems = [request]
        let completed = expectation(description: "Safari extension diagnostics recorded")
        context.onComplete = {
            completed.fulfill()
        }

        SafariWebExtensionHandler().beginRequest(with: context)
        wait(for: [completed], timeout: 2.0)

        let export = ExternalSurfaceDiagnosticsStore.shared.exportText(limit: 10)
        XCTAssertTrue(export.contains("[safari_extension] begin_request: Received Safari extension request."))
        XCTAssertTrue(export.contains("action=save_url"))
        XCTAssertTrue(export.contains("url=https://example.com"))
        XCTAssertFalse(export.contains("url=https://example.com/"))
        XCTAssertFalse(export.contains("url=https://example.com?"))
        XCTAssertFalse(export.contains("private/path"))
        XCTAssertFalse(export.contains("token=secret"))
        XCTAssertFalse(export.contains("fragment"))
        XCTAssertTrue(export.contains("process_name="))
        XCTAssertFalse(export.contains("bundle_path="))
    }

    func testSafariSaveResponsesMatchQueueAndErrorMapping() async {
        let url = "https://example.com/article"
        let message: [String: Any] = [
            "action": "save_url",
            "url": url
        ]

        do {
            let store = makeStore()
            var savedURL: String?
            var refreshCalled = false
            let payload = await SafariExtensionMessageHandler.responsePayload(
                for: message,
                pendingStore: store,
                saveWebsite: { url in savedURL = url },
                refreshAccessToken: {
                    refreshCalled = true
                    return true
                }
            )

            XCTAssertEqual(savedURL, url)
            XCTAssertFalse(refreshCalled)
            XCTAssertEqual(payload["ok"] as? Bool, true)
            XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.websiteSaved.rawValue)
            XCTAssertEqual(
                payload["message"] as? String,
                ExtensionUserMessageCatalog.message(for: .websiteSaved)
            )
            XCTAssertTrue(store.loadAll().isEmpty)
        }

        do {
            let store = makeStore()
            let payload = await SafariExtensionMessageHandler.responsePayload(
                for: message,
                pendingStore: store,
                saveWebsite: { _ in throw APIClientError.requestFailed(408) }
            )

            XCTAssertEqual(payload["ok"] as? Bool, true)
            XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.savedForLater.rawValue)
            XCTAssertEqual(
                payload["message"] as? String,
                ExtensionUserMessageCatalog.message(for: .savedForLater)
            )
            XCTAssertEqual(store.loadAll().count, 1)
        }

        do {
            let store = makeStore()
            let error = APIClientError.apiError("Unable to save website")
            let payload = await SafariExtensionMessageHandler.responsePayload(
                for: message,
                pendingStore: store,
                saveWebsite: { _ in throw error }
            )

            XCTAssertEqual(payload["ok"] as? Bool, true)
            XCTAssertEqual(payload["code"] as? String, ExtensionMessageCode.savedForLater.rawValue)
            XCTAssertEqual(
                payload["message"] as? String,
                ExtensionUserMessageCatalog.message(for: .savedForLater)
            )
            XCTAssertEqual(store.loadAll().count, 1)
        }
    }

    func testSafariAuthRefresherInitRejectsPlaceholderConfigValues() throws {
        let store = KeychainAuthStateStore(
            service: "SafariExtensionCoverage.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        let bundle = try makeConfigBundle(
            supabaseURL: "$(SUPABASE_URL)",
            anonKey: "anon-key"
        )

        XCTAssertNil(SafariExtensionAuthRefresher(keychain: store, bundle: bundle))
    }

    func testSafariAuthRefresherInitAcceptsEscapedConfigValues() throws {
        let store = KeychainAuthStateStore(
            service: "SafariExtensionCoverage.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        let bundle = try makeConfigBundle(
            supabaseURL: " https:\\/\\/example.supabase.co ",
            anonKey: " anon-key "
        )

        XCTAssertNotNil(SafariExtensionAuthRefresher(keychain: store, bundle: bundle))
    }

    func testSafariAuthRefresherReturnsFalseWhenTokenMissing() async throws {
        let store = KeychainAuthStateStore(
            service: "SafariExtensionCoverage.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        let bundle = try makeConfigBundle(
            supabaseURL: "https://example.supabase.co",
            anonKey: "anon-key"
        )
        let refresher = try XCTUnwrap(
            SafariExtensionAuthRefresher(keychain: store, bundle: bundle)
        )

        let isValid = await refresher.ensureValidSession()
        XCTAssertFalse(isValid)
    }

    func testSafariAuthRefresherSkipsRefreshWhenJwtExpiryIsHealthy() async throws {
        let store = KeychainAuthStateStore(
            service: "SafariExtensionCoverage.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        try store.saveAccessToken(makeJWT(expClaim: .number(4_102_444_800)))

        let bundle = try makeConfigBundle(
            supabaseURL: "https://example.supabase.co",
            anonKey: "anon-key"
        )
        let refresher = try XCTUnwrap(
            SafariExtensionAuthRefresher(keychain: store, bundle: bundle)
        )

        let isValid = await refresher.ensureValidSession()
        XCTAssertTrue(isValid)
    }

    func testSafariAuthRefresherSupportsStringExpClaims() async throws {
        let store = KeychainAuthStateStore(
            service: "SafariExtensionCoverage.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        try store.saveAccessToken(makeJWT(expClaim: .string("4102444800")))

        let bundle = try makeConfigBundle(
            supabaseURL: "https://example.supabase.co",
            anonKey: "anon-key"
        )
        let refresher = try XCTUnwrap(
            SafariExtensionAuthRefresher(keychain: store, bundle: bundle)
        )

        let isValid = await refresher.ensureValidSession()
        XCTAssertTrue(isValid)
    }

    func testSafariAuthRefresherReturnsFalseWhenRefreshFails() async throws {
        let store = KeychainAuthStateStore(
            service: "SafariExtensionCoverage.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        try store.saveAccessToken("invalid-token")

        let bundle = try makeConfigBundle(
            supabaseURL: "http://127.0.0.1:1",
            anonKey: "anon-key"
        )
        let refresher = try XCTUnwrap(
            SafariExtensionAuthRefresher(keychain: store, bundle: bundle)
        )

        let isValid = await refresher.ensureValidSession()
        XCTAssertFalse(isValid)
    }

    func testSafariAuthCoordinatorReturnsFalseWithoutStoredSession() async {
        let isValid = await SafariExtensionAuthCoordinator.forceRefreshAccessToken()
        XCTAssertFalse(isValid)
    }

    func testSafariExtensionEntitlementsUseUnprefixedKeychainAccessGroupTemplate() throws {
        let repositoryRoot = try findRepositoryRoot()
        let entitlementsPaths = [
            repositoryRoot
                .appendingPathComponent("ios/sideBar/sideBar Safari Extension/sideBar Safari Extension.entitlements")
                .path,
            repositoryRoot
                .appendingPathComponent(
                    "ios/sideBar/sideBar Safari Extension (macOS) Extension/sideBar Safari Extension (macOS) Extension.entitlements"
                )
                .path
        ]

        for entitlementsPath in entitlementsPaths {
            let content = try String(contentsOfFile: entitlementsPath, encoding: .utf8)
            XCTAssertTrue(content.contains("<string>$(KEYCHAIN_ACCESS_GROUP)</string>"))
            XCTAssertFalse(content.contains("$(AppIdentifierPrefix)$(KEYCHAIN_ACCESS_GROUP)"))
        }
    }

    func testMainAppEntitlementsIncludeWebCredentialsDomain() throws {
        let repositoryRoot = try findRepositoryRoot()
        let entitlementsPath = repositoryRoot
            .appendingPathComponent("ios/sideBar/sideBar/sideBar.entitlements")
            .path
        let content = try String(contentsOfFile: entitlementsPath, encoding: .utf8)

        XCTAssertTrue(content.contains("<key>com.apple.developer.associated-domains</key>"))
        XCTAssertTrue(content.contains("<string>$(ASSOCIATED_DOMAINS)</string>"))
    }

    func testSafariHandlersUseExplicitQueueOnlyURLContract() throws {
        let repositoryRoot = try findRepositoryRoot()
        let handlerPaths = [
            "ios/sideBar/sideBar Safari Extension/SafariWebExtensionHandler.swift",
            "ios/sideBar/sideBar Safari Extension (macOS) Extension/SafariWebExtensionHandler.swift"
        ]

        for relativePath in handlerPaths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertTrue(source.contains("ExtensionURLMessageHandler.handleSaveURLMessage("))
            XCTAssertTrue(source.contains("saveStrategy: .queueOnly"))
        }
    }

    private func makeStore() -> PendingShareStore {
        let temporarySuiteName = "\(suiteName).\(UUID().uuidString)"
        temporarySuiteNames.append(temporarySuiteName)
        let defaults = UserDefaults(suiteName: temporarySuiteName)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return PendingShareStore(baseDirectory: directory, userDefaults: defaults)
    }

    private func findRepositoryRoot(filePath: String = #filePath) throws -> URL {
        var candidate = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while candidate.path != "/" {
            let projectFile = candidate
                .appendingPathComponent("ios/sideBar/sideBar.xcodeproj/project.pbxproj")
            if FileManager.default.fileExists(atPath: projectFile.path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw NSError(domain: "SafariExtensionCoverageTests", code: 1)
    }

    private func makeConfigBundle(
        supabaseURL: String,
        anonKey: String
    ) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SafariExtensionCoverage.\(UUID().uuidString).bundle",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let plistURL = bundleURL.appendingPathComponent("Info.plist")
        let payload: [String: Any] = [
            "CFBundleIdentifier": "ai.sidebar.tests.safari-extension-coverage.\(UUID().uuidString)",
            "CFBundleName": "SafariExtensionCoverage",
            "CFBundlePackageType": "BNDL",
            "SUPABASE_URL": supabaseURL,
            "SUPABASE_ANON_KEY": anonKey
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)
        temporaryBundles.append(bundleURL)

        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    private enum JWTExpClaim {
        case number(TimeInterval)
        case string(String)
    }

    private func makeJWT(expClaim: JWTExpClaim) -> String {
        let header = #"{"alg":"HS256","typ":"JWT"}"#
        let payload: String
        switch expClaim {
        case .number(let exp):
            payload = #"{"exp":\#(Int(exp))}"#
        case .string(let exp):
            payload = #"{"exp":"\#(exp)"}"#
        }
        return "\(base64URL(header)).\(base64URL(payload)).signature"
    }

    private func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
