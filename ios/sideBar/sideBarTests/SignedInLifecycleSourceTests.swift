import XCTest

final class SignedInLifecycleSourceTests: XCTestCase {
    func testSignedInSceneActivationUsesCentralActivationHelper() throws {
        let normalized = try source(named: "Views/ContentView+SignedIn.swift")
            .normalizedForSourceAssertions()

        XCTAssertTrue(normalized.contains("awaitenvironment.handleSignedInActivation()"))
        XCTAssertFalse(
            normalized.contains(
                "awaitenvironment.tasksViewModel.load(selection:environment.tasksViewModel.preferredLoadSelection,force:true)"
            )
        )
        XCTAssertFalse(normalized.contains("awaitenvironment.tasksViewModel.loadCounts(force:true)"))
        XCTAssertFalse(normalized.contains("awaitenvironment.websitesViewModel.load(force:true)"))
        XCTAssertFalse(normalized.contains("awaitenvironment.chatViewModel.loadConversations(force:true)"))
    }
}

private extension String {
    func normalizedForSourceAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}

private func source(
    named relativePath: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
    let sourceURL = sideBarRoot.appendingPathComponent(relativePath)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(relativePath): \(error)", file: file, line: line)
        throw error
    }
}
