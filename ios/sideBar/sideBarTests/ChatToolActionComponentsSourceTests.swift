import XCTest

final class ChatToolActionComponentsSourceTests: XCTestCase {
    func testConfirmationActionsRenderAsButtonRowOnly() throws {
        let normalized = try chatToolActionComponentsSource().normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains("case.confirmation:confirmationControls"),
            "Confirmation actions should render the decision controls directly."
        )
        XCTAssertFalse(
            normalized.contains("case.confirmation:undoCard"),
            "Confirmation actions should not use the framed action card."
        )
    }

    func testResolvedConfirmationActionsRenderNothing() throws {
        let normalized = try chatToolActionComponentsSource().normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains("case.confirmationwhereisResolvedConfirmation:EmptyView()"),
            "Resolved confirmations should disappear instead of showing disabled buttons or a status label."
        )
    }

    private func chatToolActionComponentsSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sideBar/Views/Chat/ChatToolActionComponents.swift")
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            XCTFail("Failed to read ChatToolActionComponents source: \(error)", file: file, line: line)
            throw error
        }
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}
