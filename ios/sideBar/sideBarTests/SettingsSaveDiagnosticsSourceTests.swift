import XCTest

final class SettingsSaveDiagnosticsSourceTests: XCTestCase {
    func testSettingsSaveDiagnosticsAvoidPublicFreeFormErrorDetails() throws {
        let source = try settingsSaveDiagnosticsSource()

        XCTAssertFalse(source.contains("String(describing: apiError)"))
        XCTAssertFalse(source.contains("detail="))
        XCTAssertFalse(source.contains("error=\\(message)"))
        XCTAssertTrue(source.contains("diagnosticCode(for:"))
        XCTAssertTrue(source.contains("diagnosticStatus(for:"))
    }
}

private func settingsSaveDiagnosticsSource(file: StaticString = #filePath) throws -> String {
    let sourceURL = URL(fileURLWithPath: "\(file)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("ViewModels")
        .appendingPathComponent("SettingsViewModel+SaveDiagnostics.swift")

    return try String(contentsOf: sourceURL, encoding: .utf8)
}
