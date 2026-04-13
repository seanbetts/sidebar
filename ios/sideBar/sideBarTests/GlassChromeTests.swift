import XCTest
@testable import sideBar

@MainActor
final class GlassChromeTests: XCTestCase {
    func testPillChromeUsesCapsuleShape() {
        XCTAssertEqual(GlassChrome.tokens(for: .pill).shape, .capsule)
    }

    func testPillChromeUsesInteractiveMaterial() {
        XCTAssertEqual(GlassChrome.tokens(for: .pill).material, .interactive)
    }

    func testCardChromeUsesRoundedRectShape() {
        XCTAssertEqual(
            GlassChrome.tokens(for: .card).shape,
            .roundedRectangle(cornerRadius: DesignTokens.Radius.md)
        )
    }

    func testFieldChromeFallsBackToInputFill() {
        XCTAssertEqual(GlassChrome.tokens(for: .field).fallbackFill, .input)
    }

    func testPopoverShellChromeUsesLargeRoundedRectShape() {
        XCTAssertEqual(
            GlassChrome.tokens(for: .popoverShell).shape,
            .roundedRectangle(cornerRadius: DesignTokens.Radius.lg)
        )
    }
}
