import XCTest
@testable import sideBar

final class TransientChromePrimitiveSourceTests: XCTestCase {
    func testGlassChromeDefinesSemanticStatusAndMetadataPillKinds() {
        XCTAssertEqual(GlassChrome.tokens(for: .statusPill).shape, .capsule)
        XCTAssertEqual(GlassChrome.tokens(for: .statusPill).material, .regular)
        XCTAssertEqual(GlassChrome.tokens(for: .statusPill).fallbackFill, .surface)

        XCTAssertEqual(GlassChrome.tokens(for: .metadataPill).shape, .capsule)
        XCTAssertEqual(GlassChrome.tokens(for: .metadataPill).material, .regular)
        XCTAssertEqual(GlassChrome.tokens(for: .metadataPill).fallbackFill, .surface)
    }

    func testStatusPillSourceDefinesSemanticStatesAndUsesSharedStatusChrome() throws {
        let normalized = try source(named: "Design/Components/StatusPill.swift")

        XCTAssertTrue(normalized.contains("enumStatusPillTone:String,CaseIterable{"))
        XCTAssertTrue(normalized.contains("caseneutral"))
        XCTAssertTrue(normalized.contains("casesuccess"))
        XCTAssertTrue(normalized.contains("casewarning"))
        XCTAssertTrue(normalized.contains("caseerror"))
        XCTAssertTrue(normalized.contains("caseloading"))
        XCTAssertTrue(normalized.contains(".glassChrome(.statusPill)"))
    }

    func testMetadataPillSourceUsesSharedMetadataChromeAndCaption2Typography() throws {
        let normalized = try source(named: "Design/Components/MetadataPill.swift")

        XCTAssertTrue(normalized.contains("structMetadataPill<LeadingAccessory:View>:View{"))
        XCTAssertTrue(normalized.contains(".glassChrome(.metadataPill)"))
        XCTAssertTrue(normalized.contains(".appFont(.caption)"))
        XCTAssertTrue(normalized.contains(".foregroundStyle(DesignTokens.Colors.textSecondary)"))
    }

    private func source(named relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("sideBar").appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}
