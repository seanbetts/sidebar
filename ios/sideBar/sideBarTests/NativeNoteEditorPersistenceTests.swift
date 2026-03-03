import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorPersistenceTests: XCTestCase {
    func testCurrentPersistenceSnapshotExportsPlainTextAndCanonicalRTF() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.plainText, "hello")
        XCTAssertFalse(snapshot.canonicalContent.isEmpty)
        XCTAssertEqual(
            NotesRichTextCodec.decodeBase64RTFToPlainText(snapshot.canonicalContent),
            "hello"
        )
    }
}
