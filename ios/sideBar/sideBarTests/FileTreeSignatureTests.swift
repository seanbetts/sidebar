import XCTest
@testable import sideBar

final class FileTreeSignatureTests: XCTestCase {
    func testSignatureIncludesNodeProperties() {
        let tree = FileTree(children: [
            FileNode(
                name: "Doc",
                path: "/doc.md",
                type: .file,
                size: 10,
                modified: 100,
                children: nil,
                expanded: nil,
                pinned: true,
                pinnedOrder: 1,
                archived: false,
                folderMarker: nil
            )
        ])

        let signature = FileTreeSignature.make(tree)

        XCTAssertEqual(signature.count, 1)
        XCTAssertTrue(signature.first?.contains("Doc") == true)
        XCTAssertTrue(signature.first?.contains("/doc.md") == true)
    }

    func testSignatureSortsEntries() {
        let first = FileNode(
            name: "B",
            path: "/b.md",
            type: .file,
            size: nil,
            modified: nil,
            children: nil,
            expanded: nil,
            pinned: nil,
            pinnedOrder: nil,
            archived: nil,
            folderMarker: nil
        )
        let second = FileNode(
            name: "A",
            path: "/a.md",
            type: .file,
            size: nil,
            modified: nil,
            children: nil,
            expanded: nil,
            pinned: nil,
            pinnedOrder: nil,
            archived: nil,
            folderMarker: nil
        )

        let tree = FileTree(children: [first, second])
        let signature = FileTreeSignature.make(tree)

        XCTAssertEqual(signature, signature.sorted())
    }
}
