import XCTest

final class Task15ChatToolErrorIconSourceTests: XCTestCase {
    func testChatToolAndErrorChromeUsesAppIconVocabulary() throws {
        try assertChatToolErrorVocabularyExists()
        try assertChatMessageCopyFeedbackUsesAppIcon()
        try assertChatErrorChromeUsesAppIcon()
        try assertChatToolActionsUseAppIcon()
        try assertChatToolSummaryUsesAppIcon()
    }

    private func assertChatToolErrorVocabularyExists() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])

        XCTAssertTrue(appIcon.contains("publicstaticletundo=AppIcon(rawValue:\"arrow.uturn.backward\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletmultiple=AppIcon(rawValue:\"square.stack.3d.up\")"))
    }

    private func assertChatMessageCopyFeedbackUsesAppIcon() throws {
        let messageRow = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatMessageRow.swift"])

        XCTAssertTrue(messageRow.contains("varappIcon:AppIcon"))
        XCTAssertTrue(messageRow.contains("isCopied?AppIcon.State.successCircle:AppIcon.Action.copy"))
        XCTAssertTrue(messageRow.contains("Image(appIcon:copyFeedback.appIcon)"))
        XCTAssertFalse(messageRow.contains("variconName:String"))
        XCTAssertFalse(messageRow.contains("isCopied?\"checkmark.circle\":\"doc.on.doc\""))
        XCTAssertFalse(messageRow.contains("Image(systemName:copyFeedback.iconName)"))
    }

    private func assertChatErrorChromeUsesAppIcon() throws {
        let banners = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatToolBanners.swift"])
        let errors = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatErrorComponents.swift"])

        XCTAssertTrue(banners.contains("Image(appIcon:AppIcon.State.warningFilled)"))
        XCTAssertFalse(banners.contains("Image(systemName:\"exclamationmark.triangle.fill\")"))

        XCTAssertTrue(errors.contains("Image(appIcon:AppIcon.State.warningFilled)"))
        XCTAssertTrue(errors.contains("Image(appIcon:AppIcon.State.retry)"))
        XCTAssertFalse(errors.contains("Image(systemName:\"exclamationmark.triangle.fill\")"))
        XCTAssertFalse(errors.contains("Image(systemName:\"arrow.clockwise\")"))
    }

    private func assertChatToolActionsUseAppIcon() throws {
        let actions = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatToolActionComponents.swift"])

        XCTAssertTrue(actions.contains("icon:AppIcon.Action.close"))
        XCTAssertTrue(actions.contains("icon:AppIcon.State.success"))
        XCTAssertTrue(actions.contains("icon:AppIcon.Action.undo"))
        XCTAssertTrue(actions.contains("icon:AppIcon.State.retry"))
        XCTAssertTrue(actions.contains("Label(title,systemImage:icon.rawValue)"))
        XCTAssertFalse(actions.contains("systemImage:\"xmark\""))
        XCTAssertFalse(actions.contains("systemImage:\"checkmark\""))
        XCTAssertFalse(actions.contains("systemImage:\"arrow.uturn.backward\""))
        XCTAssertFalse(actions.contains("systemImage:\"arrow.clockwise\""))
        XCTAssertFalse(actions.contains("systemImage:String"))
    }

    private func assertChatToolSummaryUsesAppIcon() throws {
        let toolComponents = try normalizedSource(at: ["sideBar", "Views", "Chat", "ChatToolComponents.swift"])
        let skillIconView = try normalizedSource(at: ["sideBar", "Views", "Common", "SkillIconView.swift"])
        let resolver = try normalizedSource(at: ["sideBar", "Utilities", "SkillIconResolver.swift"])

        XCTAssertTrue(toolComponents.contains("leticon:AppIcon"))
        XCTAssertTrue(toolComponents.contains("AppIcon.State.error"))
        XCTAssertTrue(toolComponents.contains("AppIcon.Skills.multiple"))
        XCTAssertTrue(toolComponents.contains("SkillIconResolver.appIcon(for:toolCall)"))
        XCTAssertTrue(toolComponents.contains("SkillSymbolIcon(appIcon:summaryIcon"))
        XCTAssertTrue(toolComponents.contains("Image(appIcon:AppIcon.State.successFilled)"))
        XCTAssertFalse(toolComponents.contains("iconName=hasError?\"exclamationmark.circle\""))
        XCTAssertFalse(toolComponents.contains("\"square.stack.3d.up\""))
        XCTAssertFalse(toolComponents.contains("Image(systemName:\"checkmark.circle.fill\")"))

        XCTAssertTrue(skillIconView.contains("init(appIcon:AppIcon"))
        XCTAssertTrue(skillIconView.contains("systemName:appIcon.rawValue"))
        XCTAssertTrue(resolver.contains("staticfuncappIcon(fortoolCall:ToolCall)->AppIcon"))
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
