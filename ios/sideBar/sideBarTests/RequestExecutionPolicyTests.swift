import XCTest
import sideBarShared

final class RequestExecutionPolicyTests: XCTestCase {
    func testForegroundMutationPostCanOptIntoAuthRefreshWhenReplaySafe() {
        let intent = RequestIntent(
            operation: "settings.profileImage.upload",
            path: "settings/profile-image",
            method: .post,
            requestKind: .multipartUpload,
            authRequirement: .required,
            replaySafety: .safeToReplayBeforeBodyStarts,
            timeoutClass: .long
        )

        XCTAssertTrue(RequestExecutionPolicy.shouldAttemptAuthRefresh(for: intent))
    }

    func testNonRepeatableUploadCannotAuthRefreshAfterBodyStarts() {
        let intent = RequestIntent(
            operation: "files.upload",
            path: "files",
            method: .post,
            requestKind: .multipartUpload,
            authRequirement: .required,
            replaySafety: .notReplaySafe,
            timeoutClass: .long
        )

        XCTAssertFalse(RequestExecutionPolicy.shouldAttemptAuthRefresh(for: intent))
    }
}
