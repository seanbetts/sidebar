import XCTest

final class TypographySourceCleanupTests: XCTestCase {
    func testTypographySourceFilesDoNotUseDeprecatedAppFontStyleNames() throws {
        let sources = try swiftSources(
            under: sourceRoot.appendingPathComponent("sideBar")
        )
        let deprecatedTokens = [
            ".appFont(.title2)",
            ".appFont(.title2Semibold)",
            ".appFont(.title3Semibold)",
            ".appFont(.size16Semibold)",
            ".appFont(.labelMd)",
            ".appFont(.bodySemibold)",
            ".appFont(.headline)",
            ".appFont(.subheadline)",
            ".appFont(.subheadlineSemibold)",
            ".appFont(.callout)",
            ".appFont(.footnoteSemibold)",
            ".appFont(.captionSemibold)",
            ".appFont(.caption2)",
            ".appFont(.caption2Semibold)",
            ".appFont(.size10Bold)",
            ".appFont(.size18Semibold)",
            ".appFont(.size24Semibold)",
            ".appFont(.size32Regular)",
            ".appFont(.size32Semibold)"
        ]

        for source in sources {
            for token in deprecatedTokens {
                XCTAssertFalse(
                    source.contents.contains(token),
                    "\(source.path.lastPathComponent) still contains \(token)"
                )
            }
        }
    }

    func testOnboardingViewsUseAppFontTokens() throws {
        let sources = try swiftSources(
            under: sourceRoot
                .appendingPathComponent("sideBar")
                .appendingPathComponent("Views")
                .appendingPathComponent("Onboarding")
        )

        for source in sources {
            XCTAssertFalse(
                source.contents.contains(".font(.system"),
                "\(source.path.lastPathComponent) still uses an inline system font"
            )
            XCTAssertFalse(
                source.contents.contains(".font(."),
                "\(source.path.lastPathComponent) should use .appFont tokens instead of direct .font modifiers"
            )
        }
    }

    func testSettingsTabsViewUsesBodyTypographyToken() throws {
        let source = try sourceFile("sideBar/Views/Settings/SettingsView+Tabs.swift")

        XCTAssertTrue(source.contains(".appFont(.body)"))
        XCTAssertFalse(source.contains(".appFont(.subheading)"))
    }

    func testHeaderStatusTextAvoidsExplicitBoldWeights() throws {
        let normalized = try normalizedSourceFile("sideBar/Views/Websites/SiteHeaderBar.swift")

        XCTAssertTrue(normalized.contains("Text(text).appFont(.body)"))
        XCTAssertFalse(normalized.contains(".fontWeight(.bold)"))
        XCTAssertFalse(normalized.contains(".fontWeight(.semibold)"))
    }

    func testSharedPlaceholderDescriptionsUseBodyTypography() throws {
        let panelPlaceholder = try normalizedSourceFile("sideBar/Views/Common/SidebarPanelPlaceholder.swift")
        let sparseStateRow = try normalizedSourceFile("sideBar/Views/Common/SidebarSparseStateRow.swift")

        XCTAssertTrue(panelPlaceholder.contains("Text(subtitle).appFont(.body)"))
        XCTAssertFalse(panelPlaceholder.contains("Text(subtitle).appFont(.subheading)"))
        XCTAssertFalse(panelPlaceholder.contains(".fontWeight(.semibold)"))
        XCTAssertTrue(sparseStateRow.contains("Text(subtitle).appFont(.body)"))
        XCTAssertFalse(sparseStateRow.contains("Text(subtitle).appFont(.subheading)"))
    }

    func testSettingsAndTaskChromeAvoidRawOrRedundantFontWeights() throws {
        let settingsView = try normalizedSourceFile("sideBar/Views/Settings/SettingsView.swift")
        let tasksDetail = try normalizedSourceFile("sideBar/Views/Tasks/TasksDetailView.swift")

        XCTAssertFalse(settingsView.contains(".font(.system(size:18,weight:.semibold))"))
        XCTAssertTrue(settingsView.contains("Image(appIcon:AppIcon.Action.clearFilled).appFont(.body)"))
        XCTAssertFalse(tasksDetail.contains("Text(title).appFont(.subheading).fontWeight(.semibold)"))
    }

    func testToastBannerUsesRationalizedStatusPillTypography() throws {
        let toastSource = try sourceFile("sideBar/Design/Components/ToastCenter.swift")
        let pillSource = try sourceFile("sideBar/Design/Components/StatusPill.swift")
        let combined = toastSource + pillSource
        let normalizedPillSource = try normalizedSourceFile("sideBar/Design/Components/StatusPill.swift")

        XCTAssertTrue(combined.contains("style: .banner"))
        XCTAssertTrue(normalizedPillSource.contains("case.banner:return.body"))
        XCTAssertFalse(combined.contains(".labelMd"))
        XCTAssertFalse(combined.contains(".subheadline"))
        XCTAssertFalse(combined.contains(".subheadlineSemibold"))
    }

    func testChatStreamErrorsCannotUseOptionalToastCenterDelivery() throws {
        let chatTypes = try normalizedSourceFile("sideBar/ViewModels/Chat/ChatViewModelTypes.swift")
        let chatViewModel = try normalizedSourceFile("sideBar/ViewModels/Chat/ChatViewModel.swift")
        let streaming = try sourceFile("sideBar/ViewModels/Chat/ChatViewModel+Streaming.swift")
        let conversations = try sourceFile("sideBar/ViewModels/Chat/ChatViewModel+Conversations.swift")

        XCTAssertTrue(chatTypes.contains("lettoastCenter:ToastCenter"))
        XCTAssertTrue(chatViewModel.contains("vartoastCenter:ToastCenter{ui.toastCenter}"))
        XCTAssertFalse(streaming.contains("toastCenter?.show("))
        XCTAssertFalse(conversations.contains("toastCenter?.show("))
        XCTAssertFalse(conversations.contains("self?.toastCenter?.show("))
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: sourceRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func normalizedSourceFile(_ relativePath: String) throws -> String {
        try sourceFile(relativePath)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func swiftSources(under directory: URL) throws -> [(path: URL, contents: String)] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let urls = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys)
        )?.compactMap { $0 as? URL } ?? []

        return try urls
            .filter { $0.pathExtension == "swift" }
            .map { url in
                let values = try url.resourceValues(forKeys: resourceKeys)
                guard values.isRegularFile == true else {
                    return nil
                }
                return try (url, String(contentsOf: url, encoding: .utf8))
            }
            .compactMap { $0 }
    }
}
