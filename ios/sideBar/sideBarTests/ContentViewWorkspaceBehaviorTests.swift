import XCTest
@testable import sideBar

@MainActor
final class ContentViewWorkspaceBehaviorTests: XCTestCase {
    func testWorkspaceSidebarSwipePolicyCollapsesExpandedPanelOnLeftSwipe() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -120, height: 12),
            startX: 180,
            regionWidth: 800,
            isLeftPanelExpanded: true,
            isIPad: true
        )

        XCTAssertEqual(action, .collapseLeftPanel)
    }

    func testWorkspaceSidebarSwipePolicyExpandsCollapsedPanelOnRightSwipe() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: 96, height: 10),
            startX: 24,
            regionWidth: 800,
            isLeftPanelExpanded: false,
            isIPad: true
        )

        XCTAssertEqual(action, .expandLeftPanel)
    }

    func testWorkspaceSidebarSwipePolicyExpandsRightSwipeWhenNotFromEdge() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: 96, height: 6),
            startX: 280,
            regionWidth: 800,
            isLeftPanelExpanded: false,
            isIPad: true
        )

        XCTAssertEqual(action, .expandLeftPanel)
    }

    func testWorkspaceSidebarSwipePolicyIgnoresMostlyVerticalSwipes() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -140, height: 140),
            startX: 200,
            regionWidth: 800,
            isLeftPanelExpanded: true,
            isIPad: true
        )

        XCTAssertEqual(action, .none)
    }

    func testWorkspaceSidebarSwipePolicyDisablesSwipesWhenNotIPad() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -180, height: 10),
            startX: 180,
            regionWidth: 800,
            isLeftPanelExpanded: true,
            isIPad: false
        )

        XCTAssertEqual(action, .none)
    }

    func testWorkspaceSidebarSwipePolicyIgnoresGesturesOutsideMainRegion() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -140, height: 8),
            startX: 920,
            regionWidth: 800,
            isLeftPanelExpanded: true,
            isIPad: true
        )

        XCTAssertEqual(action, .none)
    }

    func testWorkspaceSidebarSwipePolicyCollapsesWhenSwipeStartsInSecondaryWorkspacePane() {
        let action = WorkspaceSidebarSwipePolicy.resolveAction(
            translation: CGSize(width: -120, height: 8),
            startX: 920,
            regionWidth: 1100,
            isLeftPanelExpanded: true,
            isIPad: true
        )

        XCTAssertEqual(action, .collapseLeftPanel)
    }

    func testWorkspaceBehaviorPolicyExpandedChangeCollapsesLeftPanelWhenExpanded() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceExpandedChangePlan(
            isExpanded: true,
            isLeftPanelExpanded: true,
            previousLeftPanelExpanded: nil
        )

        XCTAssertFalse(plan.isLeftPanelExpanded)
        XCTAssertEqual(plan.previousLeftPanelExpanded, true)
        XCTAssertFalse(plan.clearExpandedByRotation)
    }

    func testWorkspaceBehaviorPolicyExpandedChangeRestoresLeftPanelWhenCollapsed() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceExpandedChangePlan(
            isExpanded: false,
            isLeftPanelExpanded: false,
            previousLeftPanelExpanded: true
        )

        XCTAssertTrue(plan.isLeftPanelExpanded)
        XCTAssertNil(plan.previousLeftPanelExpanded)
        XCTAssertTrue(plan.clearExpandedByRotation)
    }

    func testWorkspaceBehaviorPolicyExpandedChangeNoopWhenNoPreviousState() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceExpandedChangePlan(
            isExpanded: false,
            isLeftPanelExpanded: false,
            previousLeftPanelExpanded: nil
        )

        XCTAssertFalse(plan.isLeftPanelExpanded)
        XCTAssertNil(plan.previousLeftPanelExpanded)
        XCTAssertFalse(plan.clearExpandedByRotation)
    }

    func testWorkspaceBehaviorPolicyRotationPlanReturnsNilWhenNotIPad() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceRotationPlan(
            isIPad: false,
            previousIsPortrait: nil,
            size: CGSize(width: 768, height: 1024),
            primaryWorkspaceSection: .chat,
            isWorkspaceExpanded: false,
            isWorkspaceExpandedByRotation: false
        )

        XCTAssertNil(plan)
    }

    func testWorkspaceBehaviorPolicyRotationPlanReturnsNilWhenOrientationUnchanged() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceRotationPlan(
            isIPad: true,
            previousIsPortrait: true,
            size: CGSize(width: 820, height: 1180),
            primaryWorkspaceSection: .chat,
            isWorkspaceExpanded: false,
            isWorkspaceExpandedByRotation: false
        )

        XCTAssertNil(plan)
    }

    func testWorkspaceBehaviorPolicyRotationPlanTracksOrientationForNonPrimarySection() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceRotationPlan(
            isIPad: true,
            previousIsPortrait: false,
            size: CGSize(width: 834, height: 1112),
            primaryWorkspaceSection: .settings,
            isWorkspaceExpanded: false,
            isWorkspaceExpandedByRotation: false
        )

        XCTAssertEqual(
            plan,
            WorkspaceRotationPlan(
                lastWorkspaceIsPortrait: true,
                isWorkspaceExpanded: nil,
                isWorkspaceExpandedByRotation: nil
            )
        )
    }

    func testWorkspaceBehaviorPolicyRotationPlanExpandsOnPortraitTransition() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceRotationPlan(
            isIPad: true,
            previousIsPortrait: false,
            size: CGSize(width: 834, height: 1112),
            primaryWorkspaceSection: .tasks,
            isWorkspaceExpanded: false,
            isWorkspaceExpandedByRotation: false
        )

        XCTAssertEqual(
            plan,
            WorkspaceRotationPlan(
                lastWorkspaceIsPortrait: true,
                isWorkspaceExpanded: true,
                isWorkspaceExpandedByRotation: true
            )
        )
    }

    func testWorkspaceBehaviorPolicyRotationPlanCollapsesOnLandscapeTransitionWhenAutoExpanded() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceRotationPlan(
            isIPad: true,
            previousIsPortrait: true,
            size: CGSize(width: 1180, height: 820),
            primaryWorkspaceSection: .chat,
            isWorkspaceExpanded: true,
            isWorkspaceExpandedByRotation: true
        )

        XCTAssertEqual(
            plan,
            WorkspaceRotationPlan(
                lastWorkspaceIsPortrait: false,
                isWorkspaceExpanded: false,
                isWorkspaceExpandedByRotation: false
            )
        )
    }

    func testWorkspaceBehaviorPolicyExpandButtonVisibilityPrimaryNonPhoneOnly() {
        XCTAssertTrue(
            WorkspaceBehaviorPolicy.shouldShowExpandButton(
                workspaceColumn: .primary,
                isPhoneIdiom: false
            )
        )
        XCTAssertFalse(
            WorkspaceBehaviorPolicy.shouldShowExpandButton(
                workspaceColumn: .primary,
                isPhoneIdiom: true
            )
        )
        XCTAssertFalse(
            WorkspaceBehaviorPolicy.shouldShowExpandButton(
                workspaceColumn: .secondary,
                isPhoneIdiom: false
            )
        )
    }

    func testWorkspaceBehaviorPolicyItemCloseCollapsesManualExpandedMode() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceItemClosePlan(
            isWorkspaceExpanded: true,
            isWorkspaceExpandedByRotation: false
        )

        XCTAssertEqual(
            plan,
            WorkspaceItemClosePlan(
                isWorkspaceExpanded: false,
                isWorkspaceExpandedByRotation: false
            )
        )
    }

    func testWorkspaceBehaviorPolicyItemCloseCollapsesRotationExpandedMode() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceItemClosePlan(
            isWorkspaceExpanded: true,
            isWorkspaceExpandedByRotation: true
        )

        XCTAssertEqual(
            plan,
            WorkspaceItemClosePlan(
                isWorkspaceExpanded: false,
                isWorkspaceExpandedByRotation: false
            )
        )
    }

    func testWorkspaceBehaviorPolicyItemCloseLeavesCollapsedWorkspaceCollapsed() {
        let plan = WorkspaceBehaviorPolicy.makeWorkspaceItemClosePlan(
            isWorkspaceExpanded: false,
            isWorkspaceExpandedByRotation: false
        )

        XCTAssertEqual(
            plan,
            WorkspaceItemClosePlan(
                isWorkspaceExpanded: false,
                isWorkspaceExpandedByRotation: false
            )
        )
    }
}
