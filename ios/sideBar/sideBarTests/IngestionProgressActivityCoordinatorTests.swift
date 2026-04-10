import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class IngestionActivityCoordinatorTests: XCTestCase {
    func testReconcileStartsActivityWhenServerIngestionBecomesActive() async {
        let recorder = ActivityRecorder()
        let coordinator = IngestionProgressActivityCoordinator(
            client: TestIngestionProgressActivityClient(recorder: recorder)
        )

        await coordinator.reconcile(
            items: [
                makeListItem(
                    id: "00000000-0000-0000-0000-000000000001",
                    status: "processing",
                    stage: "extracting",
                    progress: 0.25
                )
            ]
        )

        let started = await recorder.started
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started.first?.snapshot.fileID, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(started.first?.snapshot.progress, 0.25)
        XCTAssertEqual(started.first?.snapshot.status, .processing)
    }

    func testReconcileUpdatesExistingActivityWithoutStartingDuplicate() async {
        let recorder = ActivityRecorder()
        let coordinator = IngestionProgressActivityCoordinator(
            client: TestIngestionProgressActivityClient(recorder: recorder)
        )

        await coordinator.reconcile(
            items: [
                makeListItem(
                    id: "00000000-0000-0000-0000-000000000001",
                    status: "processing",
                    stage: "extracting",
                    progress: 0.2
                )
            ]
        )
        await coordinator.reconcile(
            items: [
                makeListItem(
                    id: "00000000-0000-0000-0000-000000000001",
                    status: "processing",
                    stage: "extracting",
                    progress: 0.7
                )
            ]
        )

        let started = await recorder.started
        let updated = await recorder.updated
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated.first?.activityID, "activity-00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(updated.first?.snapshot.progress, 0.7)
    }

    func testReconcileEndsActivityOnTerminalStatuses() async {
        let expectations: [(status: String, expected: IngestionProgressActivityStatus)] = [
            ("ready", .completed),
            ("failed", .failed),
            ("canceled", .canceled)
        ]

        for expectation in expectations {
            let recorder = ActivityRecorder()
            let coordinator = IngestionProgressActivityCoordinator(
                client: TestIngestionProgressActivityClient(recorder: recorder)
            )

            await coordinator.reconcile(
                items: [
                    makeListItem(
                        id: "00000000-0000-0000-0000-000000000001",
                        status: "processing",
                        stage: "extracting",
                        progress: 0.4
                    )
                ]
            )
            await coordinator.reconcile(
                items: [
                    makeListItem(
                        id: "00000000-0000-0000-0000-000000000001",
                        status: expectation.status,
                        stage: expectation.status,
                        progress: 1
                    )
                ]
            )

            let ended = await recorder.ended
            XCTAssertEqual(ended.count, 1, "Expected one end call for status \(expectation.status)")
            XCTAssertEqual(ended.first?.activityID, "activity-00000000-0000-0000-0000-000000000001")
            XCTAssertEqual(ended.first?.finalSnapshot?.status, expectation.expected)
        }
    }

    private func makeListItem(
        id: String,
        status: String,
        stage: String,
        progress: Double?
    ) -> IngestionListItem {
        IngestionListItem(
            file: IngestedFileMeta(
                id: id,
                filenameOriginal: "Quarterly Report.pdf",
                path: nil,
                mimeOriginal: "application/pdf",
                sizeBytes: 4_096,
                sha256: nil,
                pinned: false,
                pinnedOrder: nil,
                category: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-04-10T09:30:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            job: IngestionJob(
                status: status,
                stage: stage,
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: progress,
                attempts: 1,
                updatedAt: "2026-04-10T09:30:00Z"
            ),
            recommendedViewer: nil
        )
    }
}

private actor ActivityRecorder {
    struct StartedCall {
        let snapshot: IngestionProgressActivitySnapshot
    }

    struct UpdatedCall {
        let activityID: String
        let snapshot: IngestionProgressActivitySnapshot
    }

    struct EndedCall {
        let activityID: String
        let finalSnapshot: IngestionProgressActivitySnapshot?
    }

    private(set) var started: [StartedCall] = []
    private(set) var updated: [UpdatedCall] = []
    private(set) var ended: [EndedCall] = []

    func recordStart(snapshot: IngestionProgressActivitySnapshot) {
        started.append(StartedCall(snapshot: snapshot))
    }

    func recordUpdate(activityID: String, snapshot: IngestionProgressActivitySnapshot) {
        updated.append(UpdatedCall(activityID: activityID, snapshot: snapshot))
    }

    func recordEnd(activityID: String, finalSnapshot: IngestionProgressActivitySnapshot?) {
        ended.append(EndedCall(activityID: activityID, finalSnapshot: finalSnapshot))
    }
}

private struct TestIngestionProgressActivityClient: IngestionProgressActivityClient {
    let recorder: ActivityRecorder

    func start(snapshot: IngestionProgressActivitySnapshot) async -> String {
        await recorder.recordStart(snapshot: snapshot)
        return "activity-\(snapshot.fileID)"
    }

    func update(activityID: String, snapshot: IngestionProgressActivitySnapshot) async {
        await recorder.recordUpdate(activityID: activityID, snapshot: snapshot)
    }

    func end(activityID: String, finalSnapshot: IngestionProgressActivitySnapshot?) async {
        await recorder.recordEnd(activityID: activityID, finalSnapshot: finalSnapshot)
    }
}
