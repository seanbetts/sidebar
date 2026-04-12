import XCTest
@testable import sideBar

final class HeaderStatusPopoverTests: XCTestCase {
    func testSyncPopoverModelExposesRetryAndCancelOnly() {
        let model = HeaderStatusPopoverModel(
            title: "Sync error",
            message: "Some changes failed to sync.",
            rows: [
                .init(
                    id: "sync-1",
                    title: "Delete website",
                    detail: nil,
                    actions: [
                        .init(id: "retry", title: "Retry", role: .default),
                        .init(id: "cancel", title: "Cancel", role: .destructive)
                    ]
                )
            ]
        )

        XCTAssertEqual(model.rows.first?.actions.map(\.title), ["Retry", "Cancel"])
    }

    func testIngestionPopoverModelExposesCancelOnly() {
        let model = HeaderStatusPopoverModel(
            title: "Processing",
            message: "1 file is still processing.",
            rows: [
                .init(
                    id: "file-1",
                    title: "Quarterly report",
                    detail: nil,
                    actions: [
                        .init(id: "cancel", title: "Cancel", role: .cancel)
                    ]
                )
            ]
        )

        XCTAssertEqual(model.rows.first?.actions.map(\.title), ["Cancel"])
    }

    func testHeaderStatusPopoverSourceContainsNoNavigationActions() throws {
        let normalized = try headerStatusPopoverSource().normalizedForSourceAssertions()

        XCTAssertFalse(normalized.contains("Button(\"Reviewall\")"))
        XCTAssertFalse(normalized.contains("Button(\"Retryall\")"))
        XCTAssertFalse(normalized.contains("Button(\"Dismissfailed\")"))
        XCTAssertFalse(normalized.contains("Settings"))
        XCTAssertFalse(normalized.contains("IngestionCenter"))
    }

    func testSharedPillButtonUsesAnchoredMacPopoverAndCompactSheetFallback() throws {
        let normalized = try headerStatusPillButtonSource().normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("HeaderStatusPopover(model:pill.popover"))
        XCTAssertTrue(normalized.contains("MacPopoverShell(type:headerStatusPopoverPanelType(),presentationBackground:.appBackground){"))
        XCTAssertTrue(normalized.contains(".presentationCompactAdaptation(.sheet)"))
    }

    func testPillButtonResynchronizesPopoverRowsWhenPillContentChanges() throws {
        let normalized = try headerStatusPillButtonSource().normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains(".onChange(of:pill.popover){_,_in"))
        XCTAssertTrue(normalized.contains("popoverState=HeaderStatusPopoverState(rows:pill.popover.rows)"))
        XCTAssertTrue(normalized.contains("actionState=HeaderStatusActionPresentationState()"))
    }

    func testPopoverActionButtonsUseSharedIconChromeInsteadOfTextLabels() throws {
        let normalized = try headerStatusPopoverSource().normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains(".buttonStyle(HeaderStatusRowActionButtonStyle(role:action.role,isPrimary:isPrimaryAction(action)))"))
        XCTAssertFalse(normalized.contains(".buttonStyle(.borderless)"))
        XCTAssertTrue(normalized.contains("Image(systemName:actionSymbolName(action))"))
        XCTAssertFalse(normalized.contains("Text(action.title)"))
        XCTAssertTrue(normalized.contains(".accessibilityLabel(action.title)"))
    }

    func testPopoverRowsUseResponsiveLayoutWithoutNestedRowCardsOrDuplicateIcons() throws {
        let normalized = try headerStatusPopoverSource().normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("ViewThatFits(in:.horizontal)"))
        XCTAssertTrue(normalized.contains(".lineLimit(2)"))
        XCTAssertFalse(normalized.contains("HeaderStatusRowLeadingAccessory("))
        XCTAssertFalse(normalized.contains(".fill(DesignTokens.Colors.muted)"))
    }

    func testPopoverSuppressesRedundantErrorSummaryWhenRowsArePresent() throws {
        let normalized = try headerStatusPopoverSource().normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("privatevareffectiveMessage:String?"))
        XCTAssertTrue(normalized.contains("case(.error,false):returnnil"))
    }

    func testPopoverActionStateDisablesRowWhileInFlight() {
        let action = HeaderStatusActionModel(id: "retry", title: "Retry", role: .default)
        let state = HeaderStatusActionPresentationState(inFlightActionID: "retry")

        XCTAssertTrue(state.isDisabled(actionID: action.id))
        XCTAssertTrue(state.showsLoadingIndicator(actionID: action.id))
    }

    func testSyncRetryActionTargetsOnlyRetryFlow() {
        let row = HeaderStatusRowModel(
            id: "sync-1",
            title: "Delete website",
            detail: nil,
            actions: [
                .init(id: "retry", title: "Retry", role: .default),
                .init(id: "cancel", title: "Cancel", role: .destructive)
            ]
        )

        XCTAssertEqual(row.actions.map(\.title), ["Retry", "Cancel"])
        XCTAssertEqual(row.actions.first?.id, "retry")
    }

    func testSyncCancelActionTargetsOnlyCancelFlow() {
        let row = HeaderStatusRowModel(
            id: "sync-1",
            title: "Delete website",
            detail: nil,
            actions: [
                .init(id: "retry", title: "Retry", role: .default),
                .init(id: "cancel", title: "Cancel", role: .destructive)
            ]
        )

        XCTAssertEqual(row.actions.last?.id, "cancel")
        XCTAssertEqual(row.actions.last?.role, .destructive)
    }

    func testIngestionCancelActionIsTheOnlyAvailableRowAction() {
        let row = HeaderStatusRowModel(
            id: "file-1",
            title: "Quarterly report",
            detail: nil,
            actions: [.init(id: "cancel", title: "Cancel", role: .cancel)]
        )

        XCTAssertEqual(row.actions.map(\.title), ["Cancel"])
    }

    func testPopoverStateDismissesWhenLastActionableRowResolves() {
        let state = HeaderStatusPopoverState(rows: [
            .init(
                id: "sync-1",
                title: "Delete website",
                detail: nil,
                actions: [.init(id: "retry", title: "Retry", role: .default)]
            )
        ])

        let nextState = state.removingResolvedRow(id: "sync-1")

        XCTAssertTrue(nextState.shouldDismiss)
    }

    func testPopoverStateStaysOpenAndShowsInlineErrorOnActionFailure() {
        let state = HeaderStatusPopoverState(rows: [
            .init(
                id: "sync-1",
                title: "Delete website",
                detail: nil,
                actions: [.init(id: "retry", title: "Retry", role: .default)]
            )
        ])

        let nextState = state.applyingFailure(rowID: "sync-1", message: "Retry failed")

        XCTAssertFalse(nextState.shouldDismiss)
        XCTAssertEqual(nextState.inlineErrorByRowID["sync-1"], "Retry failed")
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func headerStatusPopoverSource(
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
        .appendingPathComponent("Websites")
        .appendingPathComponent("HeaderStatus")
        .appendingPathComponent("HeaderStatusPopover.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read HeaderStatusPopover.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func headerStatusPillButtonSource(
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
        .appendingPathComponent("Websites")
        .appendingPathComponent("HeaderStatus")
        .appendingPathComponent("HeaderStatusPillButton.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read HeaderStatusPillButton.swift: \(error)", file: file, line: line)
        throw error
    }
}
