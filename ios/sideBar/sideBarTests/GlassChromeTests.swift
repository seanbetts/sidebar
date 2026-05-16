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

    func testLargeFeatureCardChromeUsesLargeRoundedRectShape() {
        XCTAssertEqual(
            GlassChrome.tokens(for: .largeCard).shape,
            .roundedRectangle(cornerRadius: DesignTokens.Radius.lg)
        )
        XCTAssertEqual(GlassChrome.tokens(for: .largeCard).fallbackFill, .surface)
        XCTAssertEqual(GlassChrome.tokens(for: .largeCard).borderOpacity, 0.18)
    }

    func testExtraLargeFeatureCardChromeUsesExtraLargeRoundedRectShape() {
        XCTAssertEqual(
            GlassChrome.tokens(for: .extraLargeCard).shape,
            .roundedRectangle(cornerRadius: DesignTokens.Radius.xl)
        )
        XCTAssertEqual(GlassChrome.tokens(for: .extraLargeCard).fallbackFill, .surface)
        XCTAssertEqual(GlassChrome.tokens(for: .extraLargeCard).borderOpacity, 0.18)
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
