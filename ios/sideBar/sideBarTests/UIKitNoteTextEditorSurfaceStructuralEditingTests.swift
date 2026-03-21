#if os(iOS)
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurfaceEditingTests {
    func testOrdinaryCharacterPreflightBypassesSharedStructuralMutationLayer() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel)
        let initialSelection = viewModel.selection
        let initialContent = viewModel.attributedContent
        var persistenceSnapshotCount = 0
        viewModel.onPersistenceSnapshotComputedForTesting = {
            persistenceSnapshotCount += 1
        }

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: NSRange(location: 3, length: 0),
            replacementText: "!"
        ) ?? false

        XCTAssertTrue(handled)
        XCTAssertEqual(viewModel.selection, initialSelection)
        XCTAssertEqual(viewModel.attributedContent, initialContent)
        XCTAssertEqual(persistenceSnapshotCount, 0)
    }
}
#endif
