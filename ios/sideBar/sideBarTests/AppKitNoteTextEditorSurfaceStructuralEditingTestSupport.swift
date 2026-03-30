#if os(macOS)
import AppKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func mountedStructuralEditorSnapshot(
    from textView: NSTextView
) -> NativeNoteEditorViewModel.PersistenceSnapshot? {
    (textView.delegate as? AppKitNoteTextEditorSurface.Coordinator)?.viewModel.currentPersistenceSnapshot()
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
func codeBlockBackgroundRects(in textView: NSTextView) -> [NSRect] {
    guard let textStorage = textView.textStorage,
          let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else {
        return []
    }

    return NoteTextCodeBlockBackgroundLayout.blockRects(
        in: textStorage,
        layoutManager: layoutManager,
        textContainer: textContainer,
        textContainerInset: textView.textContainerInset
    )
}

func fontAttribute(
    in textView: NSTextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSFont {
    guard textView.string.utf16.count > location else {
        XCTFail("Expected text length > \(location), got \(textView.string.utf16.count)", file: file, line: line)
        throw AppKitNoteTextEditorSurfaceTestError.missingAttribute
    }

    return try XCTUnwrap(
        textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont,
        file: file,
        line: line
    )
}

func backgroundColorAttribute(
    in textView: NSTextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSColor {
    guard textView.string.utf16.count > location else {
        XCTFail("Expected text length > \(location), got \(textView.string.utf16.count)", file: file, line: line)
        throw AppKitNoteTextEditorSurfaceTestError.missingAttribute
    }

    return try XCTUnwrap(
        textView.textStorage?.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor,
        file: file,
        line: line
    )
}

func assertParagraphStyle(
    in textView: NSTextView,
    matches expected: NSParagraphStyle,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let actual = try XCTUnwrap(
        textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
        file: file,
        line: line
    )
    XCTAssertEqual(actual.lineSpacing, expected.lineSpacing, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.paragraphSpacingBefore, expected.paragraphSpacingBefore, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.paragraphSpacing, expected.paragraphSpacing, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.headIndent, expected.headIndent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.firstLineHeadIndent, expected.firstLineHeadIndent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.tailIndent, expected.tailIndent, accuracy: 0.001, file: file, line: line)
}

enum AppKitNoteTextEditorSurfaceTestError: Error {
    case missingAttribute
}

@MainActor
func samplePixelColor(
    in view: NSView,
    at point: NSPoint,
    file: StaticString = #filePath,
    line: UInt = #line
) -> NSColor? {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    guard let rep else {
        XCTFail("Expected bitmap image rep", file: file, line: line)
        return nil
    }

    view.cacheDisplay(in: view.bounds, to: rep)
    let pixelX = Int(point.x.rounded(.down))
    let pixelY = Int(point.y.rounded(.down))
    guard pixelX >= 0, pixelX < rep.pixelsWide, pixelY >= 0, pixelY < rep.pixelsHigh else {
        XCTFail("Sample point out of bounds: \(point)", file: file, line: line)
        return nil
    }

    return rep.colorAt(x: pixelX, y: pixelY)
}

@MainActor
func assertColorsApproximatelyNotEqual(
    _ actual: NSColor,
    _ expected: NSColor,
    tolerance: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let actualColor = actual.usingColorSpace(.deviceRGB)
    let expectedColor = expected.usingColorSpace(.deviceRGB)
    XCTAssertNotNil(actualColor, file: file, line: line)
    XCTAssertNotNil(expectedColor, file: file, line: line)
    guard let actualColor, let expectedColor else { return }

    let redDelta = abs(actualColor.redComponent - expectedColor.redComponent)
    let greenDelta = abs(actualColor.greenComponent - expectedColor.greenComponent)
    let blueDelta = abs(actualColor.blueComponent - expectedColor.blueComponent)
    let alphaDelta = abs(actualColor.alphaComponent - expectedColor.alphaComponent)
    let matchesExpectedWithinTolerance = redDelta <= tolerance &&
        greenDelta <= tolerance &&
        blueDelta <= tolerance &&
        alphaDelta <= tolerance

    XCTAssertFalse(matchesExpectedWithinTolerance, file: file, line: line)
}

@MainActor
func assertColorsApproximatelyEqual(
    _ actual: NSColor,
    _ expected: NSColor,
    tolerance: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let actualColor = actual.usingColorSpace(.deviceRGB)
    let expectedColor = expected.usingColorSpace(.deviceRGB)
    XCTAssertNotNil(actualColor, file: file, line: line)
    XCTAssertNotNil(expectedColor, file: file, line: line)
    guard let actualColor, let expectedColor else { return }

    XCTAssertEqual(actualColor.redComponent, expectedColor.redComponent, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actualColor.greenComponent, expectedColor.greenComponent, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actualColor.blueComponent, expectedColor.blueComponent, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actualColor.alphaComponent, expectedColor.alphaComponent, accuracy: tolerance, file: file, line: line)
}
#endif
