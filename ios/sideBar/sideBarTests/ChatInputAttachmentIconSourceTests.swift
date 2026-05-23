import XCTest

final class ChatInputAttachmentIconSourceTests: XCTestCase {
    func testChatInputAndAttachmentControlsUseAppIconVocabulary() throws {
        try assertChatInputVocabularyExists()
        try assertChatAttachmentsUseAppIcon()
        try assertUIKitChatInputUsesAppIcon()
        try assertAppKitChatInputUsesAppIcon()
    }

    private func assertChatInputVocabularyExists() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])

        XCTAssertTrue(appIcon.contains("publicstaticletsend=AppIcon(rawValue:\"arrow.up\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletattach=AppIcon(rawValue:\"paperclip\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletcancel=AppIcon(rawValue:\"xmark.circle\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletdelete=AppIcon(rawValue:\"trash\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletclose=AppIcon(rawValue:\"xmark\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletretry=AppIcon(rawValue:\"arrow.clockwise\")"))
    }

    private func assertChatAttachmentsUseAppIcon() throws {
        let attachments = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatAttachmentsView.swift"])

        XCTAssertTrue(attachments.contains("Image(appIcon:AppIcon.Action.attach)"))
        XCTAssertTrue(attachments.contains("Image(appIcon:AppIcon.State.retry)"))
        XCTAssertTrue(attachments.contains("Image(appIcon:AppIcon.Action.delete)"))
        XCTAssertTrue(attachments.contains("Image(appIcon:AppIcon.Action.cancel)"))
        XCTAssertTrue(attachments.contains("Image(appIcon:AppIcon.Action.close)"))
        XCTAssertFalse(attachments.contains("Image(systemName:\"paperclip\")"))
        XCTAssertFalse(attachments.contains("Image(systemName:\"arrow.clockwise\")"))
        XCTAssertFalse(attachments.contains("Image(systemName:\"trash\")"))
        XCTAssertFalse(attachments.contains("Image(systemName:\"xmark.circle\")"))
        XCTAssertFalse(attachments.contains("Image(systemName:\"xmark\")"))
    }

    private func assertUIKitChatInputUsesAppIcon() throws {
        let input = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatInputUIKit.swift"])
        let metrics = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatInputUIKit+Metrics.swift"])

        XCTAssertTrue(input.contains("makeAccessoryButton(appIcon:AppIcon.Action.attach)"))
        XCTAssertTrue(input.contains("makeAccessoryButton(appIcon:AppIcon.Action.send)"))
        XCTAssertTrue(metrics.contains("funcmakeAccessoryButton(appIcon:AppIcon)->UIButton"))
        XCTAssertTrue(metrics.contains("systemName:appIcon.rawValue"))
        XCTAssertFalse(input.contains("makeAccessoryButton(systemName:\"paperclip\")"))
        XCTAssertFalse(input.contains("makeAccessoryButton(systemName:\"arrow.up\")"))
        XCTAssertFalse(metrics.contains("funcmakeAccessoryButton(systemName:String)->UIButton"))
        XCTAssertFalse(metrics.contains("systemName:systemName"))
    }

    private func assertAppKitChatInputUsesAppIcon() throws {
        let input = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatInputAppKit.swift"])

        XCTAssertTrue(input.contains("symbolImage(for:AppIcon.Action.attach)"))
        XCTAssertTrue(input.contains("symbolImage(for:AppIcon.Action.send)"))
        XCTAssertTrue(input.contains("systemSymbolName:appIcon.rawValue"))
        XCTAssertFalse(input.contains("systemSymbolName:\"paperclip\""))
        XCTAssertFalse(input.contains("systemSymbolName:\"arrow.up\""))
    }

    private func normalizedSource(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let source = try source(at: pathComponents, file: file, line: line)
        return source.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func source(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = pathComponents.reduce(sideBarRoot) { url, component in
            url.appendingPathComponent(component)
        }

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }
}
