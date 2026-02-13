import XCTest
@testable import ShareExtension

#if canImport(UIKit)
import UIKit

final class SharePlatformImageTests: XCTestCase {
    func testShareJPEGDataReturnsEncodedPayload() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }

        let data = shareJPEGData(from: image, compressionQuality: 0.9)

        XCTAssertNotNil(data)
        XCTAssertFalse(data?.isEmpty ?? true)
    }
}
#endif
