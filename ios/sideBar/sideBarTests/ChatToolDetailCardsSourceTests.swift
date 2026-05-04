import XCTest

final class ChatToolDetailCardsSourceTests: XCTestCase {
    func testProminentInlineWorkspaceButtonsUseExplicitContrastStyle() throws {
        let normalized = try chatToolDetailCardsSource().normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains(".buttonStyle(ChatProminentInlineActionButtonStyle())"),
            "Prominent inline chat buttons need an explicit contrast style in dark mode."
        )
        XCTAssertTrue(
            normalized.contains(".foregroundStyle(DesignTokens.Colors.background)"),
            "The label color must contrast with the textPrimary button fill."
        )
        XCTAssertTrue(
            normalized.contains(".fill(DesignTokens.Colors.textPrimary"),
            "The prominent button fill should follow textPrimary for light/dark inversion."
        )
    }

    private func chatToolDetailCardsSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sideBar/Views/Chat/ChatToolDetailCards.swift")
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            XCTFail("Failed to read ChatToolDetailCards source: \(error)", file: file, line: line)
            throw error
        }
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}
