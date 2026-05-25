import XCTest

final class ReducedMotionAnimationSourceTests: XCTestCase {
    func testWorkspaceLayoutSidebarAnimationsUseMotionToken() throws {
        let normalized = try source(at: ["sideBar", "Views", "WorkspaceLayout.swift"])
            .normalizedForAnimationAssertions()

        XCTAssertTrue(normalized.contains("@Environment(\\.accessibilityReduceMotion)privatevarreduceMotion"))
        XCTAssertTrue(normalized.contains("privatevarsidebarAnimation:Animation?{"))
        XCTAssertTrue(normalized.contains("Motion.standard(reduceMotion:reduceMotion)"))
        XCTAssertTrue(normalized.contains(".animation(shouldAnimateSidebar?sidebarAnimation:nil,value:isLeftPanelExpanded)"))
        XCTAssertTrue(normalized.contains("withAnimation(sidebarAnimation)"))
        XCTAssertFalse(normalized.contains(".smooth(duration:0.3)"))
    }

    func testSiteHeaderBarSidebarAnimationUsesMotionToken() throws {
        let normalized = try source(at: ["sideBar", "Views", "Websites", "SiteHeaderBar.swift"])
            .normalizedForAnimationAssertions()

        XCTAssertTrue(normalized.contains("@Environment(\\.accessibilityReduceMotion)privatevarreduceMotion"))
        XCTAssertTrue(normalized.contains("Motion.standard(reduceMotion:reduceMotion)"))
        XCTAssertTrue(normalized.contains(".animation(shouldAnimateSidebar?sidebarAnimation:nil,value:isLeftPanelExpanded)"))
        XCTAssertFalse(normalized.contains(".smooth(duration:0.3)"))
    }

    func testTaskRowCompletionAndExpansionAnimationsUseMotionTokens() throws {
        let normalized = try source(at: ["sideBar", "Views", "Tasks", "TasksViewComponents.swift"])
            .normalizedForAnimationAssertions()

        XCTAssertTrue(normalized.contains("withAnimation(Motion.quick(reduceMotion:reduceMotion))"))
        XCTAssertTrue(normalized.contains("privatevarexpandAnimation:Animation?{Motion.quick(reduceMotion:reduceMotion)}"))
        XCTAssertFalse(normalized.contains(".easeInOut(duration:0.15)"))
        XCTAssertFalse(normalized.contains(".snappy(duration:0.22"))
        XCTAssertFalse(normalized.contains(".spring(response:0.28"))
    }

    func testLoginSuccessAnimationUsesMotionToken() throws {
        let normalized = try source(at: ["sideBar", "Views", "Auth", "LoginView.swift"])
            .normalizedForAnimationAssertions()

        XCTAssertTrue(normalized.contains("withAnimation(Motion.standard(reduceMotion:reduceMotion))"))
        XCTAssertFalse(normalized.contains(".spring(response:0.3,dampingFraction:0.8)"))
    }

    func testSignedInContentAnimationsUseMotionTokens() throws {
        let normalized = try source(at: ["sideBar", "Views", "ContentView+SignedIn.swift"])
            .normalizedForAnimationAssertions()

        XCTAssertTrue(
            normalized.contains(".animation(Motion.quick(reduceMotion:reduceMotion),value:environment.isMacSettingsPresented)")
        )
        XCTAssertTrue(
            normalized.contains(".animation(Motion.quick(reduceMotion:reduceMotion),value:environment.toastCenter.toast)")
        )
        XCTAssertFalse(normalized.contains(".easeInOut(duration:0.2)"))
        XCTAssertFalse(normalized.contains(".easeOut(duration:0.2)"))
    }
}

private func source(
    at pathComponents: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = pathComponents.reduce(sideBarRoot) { url, component in
        url.appendingPathComponent(component)
    }

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(pathComponents.joined(separator: "/")): \(error)", file: file, line: line)
        throw error
    }
}

private extension String {
    func normalizedForAnimationAssertions() -> String {
        replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}
