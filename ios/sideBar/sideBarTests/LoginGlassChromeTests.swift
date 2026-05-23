import XCTest
@testable import sideBar

@MainActor
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

    func testLoginSourcesUseUnifiedFormFieldForCredentialRows() throws {
        let normalized = try combinedLoginChromeSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertEqual(
            normalized.components(separatedBy: "FormField(leadingIcon:AppIcon.Auth.email)").count - 1,
            1
        )
        XCTAssertEqual(
            normalized.components(separatedBy: "FormField(leadingIcon:AppIcon.Auth.password)").count - 1,
            1
        )
        XCTAssertFalse(normalized.contains("LoginFieldRow("))
        XCTAssertFalse(normalized.contains("structLoginFieldRow<Content:View,Trailing:View>:View{"))
    }

    func testUnifiedFormFieldUsesSharedLoginFieldMetricsForAuthLayout() throws {
        let normalized = try formFieldSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("spacing:LoginFieldChromeMetrics.trailingControlSpacing"))
        XCTAssertTrue(normalized.contains(".sidebarTextEntrySurface()"))
        XCTAssertTrue(normalized.contains("DesignTokens.Colors.input"))
        XCTAssertTrue(normalized.contains("structFormFieldSecureInput<Field:Hashable>:View{"))
        XCTAssertTrue(normalized.contains(".font(.system(size:LoginFieldChromeMetrics.trailingSymbolPointSize))"))
    }

    func testUnifiedFormFieldUsesBodyTypographyForEditableAuthValues() throws {
        let normalized = try formFieldSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(".appFont(.body).padding(.vertical,LoginFieldChromeMetrics.fieldVerticalPadding)")
        )
        XCTAssertFalse(
            normalized.contains(".appFont(.subheading).padding(.vertical,LoginFieldChromeMetrics.fieldVerticalPadding)")
        )
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

private func formFieldSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Design")
        .appendingPathComponent("Components")
        .appendingPathComponent("FormField.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read FormField.swift: \(error)", file: file, line: line)
        throw error
    }
}
