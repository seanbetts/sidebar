import XCTest
@testable import sideBar

final class LoginGlassChromeTests: XCTestCase {
    func testLoginFieldChromeUsesSharedFieldKind() {
        XCTAssertEqual(LoginChrome.fieldKind, .field)
    }

    func testLoginNoticeChromeUsesSharedCardKind() {
        XCTAssertEqual(LoginChrome.noticeKind, .card)
    }

    func testLoginSourcesRouteFieldsAndNoticesThroughSharedGlassChrome() throws {
        let normalized = try combinedLoginChromeSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertEqual(
            normalized.components(separatedBy: ".glassChrome(LoginChrome.fieldKind)").count - 1,
            2
        )
        XCTAssertEqual(
            normalized.components(separatedBy: ".glassChrome(LoginChrome.noticeKind)").count - 1,
            3
        )
    }

    func testLoginGroupBoxStyleDoesNotWrapFieldsInAnOuterCard() throws {
        let normalized = try loginGroupBoxStyleSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains(".cardStyle()"))
    }

    func testLoginGroupBoxStyleKeepsOuterBorderWithoutRestoringCardFill() throws {
        let normalized = try loginGroupBoxStyleSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".stroke(DesignTokens.Colors.border"))
    }
}

private func combinedLoginChromeSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let authRoot = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Auth")
    let sourceURLs = [
        authRoot.appendingPathComponent("LoginView.swift"),
        authRoot.appendingPathComponent("LoginViewComponents.swift"),
        authRoot.appendingPathComponent("LoginAuthPresentation.swift")
    ]

    do {
        return try sourceURLs
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    } catch {
        XCTFail("Failed to read login chrome sources: \(error)", file: file, line: line)
        throw error
    }
}

private func loginGroupBoxStyleSource(
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
        .appendingPathComponent("Auth")
        .appendingPathComponent("LoginGroupBoxStyle.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read LoginGroupBoxStyle.swift: \(error)", file: file, line: line)
        throw error
    }
}
