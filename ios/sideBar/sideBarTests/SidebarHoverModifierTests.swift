import XCTest
@testable import sideBar

final class SidebarHoverModifierTests: XCTestCase {
    func testSidebarHoverModifierTracksHoverStateAndCursorInternally() throws {
        let normalized = try sidebarHoverModifierSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("enumSidebarHoverCursor{"))
        XCTAssertTrue(normalized.contains("casepointingHand"))
        XCTAssertTrue(normalized.contains("caseresizeLeftRight"))
        XCTAssertTrue(normalized.contains("structSidebarHoverModifier:ViewModifier{"))
        XCTAssertTrue(normalized.contains("@StateprivatevarisHovered=false"))
        XCTAssertTrue(normalized.contains("@StateprivatevarisCursorActive=false"))
        XCTAssertTrue(normalized.contains(".environment(\\.sidebarIsHovered,resolvedIsHovered)"))
        XCTAssertTrue(normalized.contains(".onHover{hoveringin"))
        XCTAssertFalse(normalized.contains("simultaneousGesture(DragGesture(minimumDistance:0)"))
        XCTAssertTrue(normalized.contains("case.pointingHand:return.pointingHand"))
        XCTAssertTrue(normalized.contains("case.resizeLeftRight:return.resizeLeftRight"))
        XCTAssertTrue(normalized.contains("funcsidebarHover(cursor:SidebarHoverCursor?=.pointingHand)->someView"))
        XCTAssertTrue(normalized.contains("funcsidebarHover(_isHovered:Binding<Bool>,cursor:SidebarHoverCursor?=.pointingHand)->someView"))
    }
}

private func sidebarHoverModifierSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Design")
        .appendingPathComponent("Modifiers")
        .appendingPathComponent("SidebarHoverModifier.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SidebarHoverModifier.swift: \(error)", file: file, line: line)
        throw error
    }
}
