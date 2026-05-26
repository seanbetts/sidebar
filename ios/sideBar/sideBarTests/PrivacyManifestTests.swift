import XCTest

final class PrivacyManifestTests: XCTestCase {
    private enum ManifestPath: String, CaseIterable {
        case app = "ios/sideBar/sideBar/PrivacyInfo.xcprivacy"
        case shared = "ios/sideBar/sideBarShared/PrivacyInfo.xcprivacy"
        case shareExtension = "ios/sideBar/ShareExtension/PrivacyInfo.xcprivacy"
        case widgets = "ios/sideBar/sideBarWidgets/PrivacyInfo.xcprivacy"
        case safariExtension = "ios/sideBar/sideBar Safari Extension/PrivacyInfo.xcprivacy"
        case safariHost = "ios/sideBar/sideBar Safari Extension (macOS)/PrivacyInfo.xcprivacy"
        case safariMacExtension = "ios/sideBar/sideBar Safari Extension (macOS) Extension/PrivacyInfo.xcprivacy"
    }

    func testAllFirstPartyAppleTargetsDeclarePrivacyManifests() throws {
        for path in ManifestPath.allCases {
            let manifest = try manifest(at: path)
            XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false, path.rawValue)
            XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [], path.rawValue)
            XCTAssertNotNil(manifest["NSPrivacyAccessedAPITypes"], path.rawValue)
            XCTAssertNotNil(manifest["NSPrivacyCollectedDataTypes"], path.rawValue)
        }
    }

    func testAppManifestDeclaresRequiredReasonApisAndCollectedData() throws {
        let manifest = try manifest(at: .app)

        XCTAssertEqual(
            accessedReasons(in: manifest)["NSPrivacyAccessedAPICategoryUserDefaults"],
            ["CA92.1", "1C8F.1"]
        )
        XCTAssertEqual(
            accessedReasons(in: manifest)["NSPrivacyAccessedAPICategorySystemBootTime"],
            ["35F9.1"]
        )
        XCTAssertEqual(
            accessedReasons(in: manifest)["NSPrivacyAccessedAPICategoryFileTimestamp"],
            ["C617.1", "3B52.1"]
        )

        XCTAssertTrue(collectedTypes(in: manifest).isSuperset(of: [
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypePreciseLocation",
            "NSPrivacyCollectedDataTypeCoarseLocation",
            "NSPrivacyCollectedDataTypePhotosorVideos",
            "NSPrivacyCollectedDataTypeOtherUserContent",
            "NSPrivacyCollectedDataTypeProductInteraction",
            "NSPrivacyCollectedDataTypeCrashData",
            "NSPrivacyCollectedDataTypePerformanceData",
            "NSPrivacyCollectedDataTypeOtherDiagnosticData"
        ]))
    }

    func testExtensionManifestsDeclareSharedContainerAndUserContentFlows() throws {
        let sharedReasons = accessedReasons(in: try manifest(at: .shared))
        XCTAssertEqual(sharedReasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["1C8F.1"])
        XCTAssertEqual(sharedReasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"])

        let shareManifest = try manifest(at: .shareExtension)
        XCTAssertTrue(collectedTypes(in: shareManifest).isSuperset(of: [
            "NSPrivacyCollectedDataTypePhotosorVideos",
            "NSPrivacyCollectedDataTypeOtherUserContent"
        ]))

        let widgetManifest = try manifest(at: .widgets)
        XCTAssertEqual(
            accessedReasons(in: widgetManifest)["NSPrivacyAccessedAPICategoryUserDefaults"],
            ["1C8F.1"]
        )
        XCTAssertTrue(collectedTypes(in: widgetManifest).contains("NSPrivacyCollectedDataTypeOtherUserContent"))

        for path in [ManifestPath.safariExtension, .safariMacExtension] {
            let manifest = try manifest(at: path)
            XCTAssertEqual(
                accessedReasons(in: manifest)["NSPrivacyAccessedAPICategoryUserDefaults"],
                ["1C8F.1"],
                path.rawValue
            )
            XCTAssertTrue(
                collectedTypes(in: manifest).contains("NSPrivacyCollectedDataTypeBrowsingHistory"),
                path.rawValue
            )
        }
    }

    private func manifest(
        at path: ManifestPath,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let url = repositoryRoot(file: file).appendingPathComponent(path.rawValue)
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any], "Invalid privacy manifest at \(path.rawValue)", file: file, line: line)
    }

    private func accessedReasons(in manifest: [String: Any]) -> [String: Set<String>] {
        let entries = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        return entries.reduce(into: [:]) { result, entry in
            guard let apiType = entry["NSPrivacyAccessedAPIType"] as? String else { return }
            let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            result[apiType] = Set(reasons)
        }
    }

    private func collectedTypes(in manifest: [String: Any]) -> Set<String> {
        let entries = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        return Set(entries.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
    }

    private func repositoryRoot(file: StaticString) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
