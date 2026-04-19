import XCTest

final class ChatToastCenterSourceTests: XCTestCase {
    func testChatUICoordinatorRequiresToastCenter() throws {
        let normalized = try source(named: "ViewModels/Chat/ChatViewModelTypes.swift")

        XCTAssertTrue(normalized.contains("lettoastCenter:ToastCenter"))
        XCTAssertFalse(normalized.contains("lettoastCenter:ToastCenter?"))
        XCTAssertFalse(normalized.contains("toastCenter:ToastCenter?=nil"))
    }

    func testChatViewModelExposesNonOptionalToastCenter() throws {
        let normalized = try source(named: "ViewModels/Chat/ChatViewModel.swift")

        XCTAssertTrue(normalized.contains("vartoastCenter:ToastCenter{ui.toastCenter}"))
        XCTAssertFalse(normalized.contains("vartoastCenter:ToastCenter?{ui.toastCenter}"))
    }

    func testChatFlowsDoNotOptionalChainToastDelivery() throws {
        let streaming = try source(named: "ViewModels/Chat/ChatViewModel+Streaming.swift")
        let conversations = try source(named: "ViewModels/Chat/ChatViewModel+Conversations.swift")

        XCTAssertFalse(streaming.contains("toastCenter?.show("))
        XCTAssertFalse(conversations.contains("toastCenter?.show("))
        XCTAssertFalse(conversations.contains("self?.toastCenter?.show("))
    }

    private func source(named filename: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("sideBar").appendingPathComponent(filename)
        return try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}
