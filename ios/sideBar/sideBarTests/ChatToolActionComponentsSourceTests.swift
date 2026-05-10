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

    func testUndoActionsRenderAsButtonRowOnlyAndDisappearWhenResolved() throws {
        let normalized = try chatToolActionComponentsSource().normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains("case.undowhereisResolvedUndo:EmptyView()"),
            "Resolved undo actions should disappear instead of showing disabled buttons or an Undone label."
        )
        XCTAssertTrue(
            normalized.contains("case.undo:undoControls"),
            "Pending undo actions should render the same direct control row as confirmations."
        )
        XCTAssertFalse(
            normalized.contains("case.undo:undoCard"),
            "Undo actions should not use a separate framed success card."
        )
    }

    func testToolActionRowsDoNotRenderInlineStatusMessages() throws {
        let normalized = try chatToolActionComponentsSource().normalizedForSourceAssertions()

        XCTAssertFalse(
            normalized.contains("statusLabel"),
            "Running and failed state should move to the app header status pill."
        )
        XCTAssertFalse(normalized.contains("Working"))
        XCTAssertFalse(normalized.contains("Failed"))
        XCTAssertFalse(normalized.contains("Confirmed"))
        XCTAssertFalse(normalized.contains("Declined"))
        XCTAssertFalse(normalized.contains("Undone"))
    }

    func testFailedToolActionsRenderRetryControl() throws {
        let normalized = try chatToolActionComponentsSource().normalizedForSourceAssertions()

        XCTAssertTrue(
            normalized.contains("case.failed:retryControls"),
            "Failed confirmation and undo actions should offer a retry control."
        )
        XCTAssertTrue(
            normalized.contains("title:\"Retry\""),
            "Retry should be the only visible failure action."
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
