import XCTest

final class ChatHangMitigationSourceTests: XCTestCase {
    func testChatViewOnlyRunsAutoRefreshWhileSceneIsActive() throws {
        let normalized = try chatViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains(".task{environment.chatViewModel.startAutoRefresh()}"))
        XCTAssertFalse(normalized.contains("Task{awaitenvironment.chatViewModel.loadConversations()}"))
        XCTAssertFalse(normalized.contains("Task{awaitenvironment.chatViewModel.refreshConversations(silent:true)}"))
        XCTAssertTrue(normalized.contains(".onAppear{updateAutoRefresh(for:scenePhase)}"))
        XCTAssertTrue(
            normalized.contains(".onChange(of:scenePhase){_,newValueinupdateAutoRefresh(for:newValue)}")
        )
        XCTAssertTrue(normalized.contains("privatefuncupdateAutoRefresh(forscenePhase:ScenePhase){"))
        XCTAssertTrue(normalized.contains("ifscenePhase==.active{environment.chatViewModel.startAutoRefresh()}"))
        XCTAssertTrue(normalized.contains("else{environment.chatViewModel.stopAutoRefresh()}"))
    }

    func testAppEnvironmentDoesNotForwardChatViewModelObjectWillChangeToRootEnvironment() throws {
        let normalized = try appEnvironmentSetupSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("chatViewModel.objectWillChange"))
        XCTAssertTrue(normalized.contains("settingsViewModel.objectWillChange"))
        XCTAssertTrue(normalized.contains("navigation.objectWillChange"))
    }

    private func chatViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Chat")
            .appendingPathComponent("ChatView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read ChatView.swift: \(error)", file: file, line: line)
            throw error
        }
    }

    private func appEnvironmentSetupSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("App")
            .appendingPathComponent("AppEnvironment+Setup.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read AppEnvironment+Setup.swift: \(error)", file: file, line: line)
            throw error
        }
    }
}
