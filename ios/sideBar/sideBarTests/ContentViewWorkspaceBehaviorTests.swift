import XCTest
@testable import sideBar
#if os(iOS)
import UIKit
#endif

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

    #if os(iOS)
    func testWorkspaceSidebarSwipeCaptureIgnoresTouchesInsideNoteFormattingHierarchy() {
        let anchorView = UIView(frame: CGRect(x: 0, y: 0, width: 1100, height: 900))
        let formattingPopover = UIView(frame: CGRect(x: 720, y: 40, width: 320, height: 220))
        formattingPopover.accessibilityIdentifier = "note-formatting-popover"
        anchorView.addSubview(formattingPopover)

        let formattingScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 60))
        formattingScrollView.accessibilityIdentifier = "note-formatting-text-style-strip"
        formattingPopover.addSubview(formattingScrollView)

        XCTAssertFalse(
            WorkspaceSidebarSwipeCaptureView.Coordinator.shouldCaptureTouch(
                touchedView: formattingScrollView,
                locationInAnchor: CGPoint(x: 760, y: 72),
                anchorBounds: anchorView.bounds,
                regionWidth: 1100
            )
        )
    }

    func testWorkspaceSidebarSwipeCaptureAcceptsTouchesOutsideNoteFormattingHierarchy() {
        let anchorView = UIView(frame: CGRect(x: 0, y: 0, width: 1100, height: 900))
        let contentView = UIView(frame: CGRect(x: 0, y: 0, width: 1100, height: 900))
        anchorView.addSubview(contentView)

        XCTAssertTrue(
            WorkspaceSidebarSwipeCaptureView.Coordinator.shouldCaptureTouch(
                touchedView: contentView,
                locationInAnchor: CGPoint(x: 420, y: 240),
                anchorBounds: anchorView.bounds,
                regionWidth: 1100
            )
        )
    }
    #endif

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

    func testScratchpadPresentationStyleUsesSheetOnPhone() {
        XCTAssertEqual(
            WorkspaceBehaviorPolicy.scratchpadPresentationStyle(isPhoneIdiom: true),
            .sheet
        )
    }

    func testScratchpadPresentationStyleUsesAnchoredPopoverOffPhone() {
        XCTAssertEqual(
            WorkspaceBehaviorPolicy.scratchpadPresentationStyle(isPhoneIdiom: false),
            .anchoredPopover
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

    func testWorkspaceResizeHandlesUseSharedHoverCursorModifier() throws {
        let workspaceNormalized = try workspaceLayoutSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let splitNormalized = try sidebarSplitViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(workspaceNormalized.contains(".sidebarHover(cursor:.resizeLeftRight)"))
        XCTAssertTrue(splitNormalized.contains(".sidebarHover(cursor:.resizeLeftRight)"))
    }

    func testWorkspaceLayoutUsesAdaptiveMacRightSidebarSnapPoints() throws {
        let normalized = try workspaceLayoutSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("adaptiveRightSidebarSnapPoints("))
        XCTAssertTrue(normalized.contains("roundedRightSidebarWidth("))
        XCTAssertFalse(normalized.contains("defaultRightSidebarWidth,420,480,maxAllowed,half"))
    }

    func testSignedInContentHandlesSidebarToggleAndScratchpadShortcutsOnMacOS() throws {
        let normalized = try signedInContentSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                ".onReceive(environment.navigation.$shortcutActionEvent){eventinguardleteventelse{return}switchevent.action{"
            )
        )
        XCTAssertTrue(normalized.contains("case.toggleSidebar:#ifos(macOS)isLeftPanelExpanded.toggle()"))
        XCTAssertTrue(
            normalized.contains(
                "case.openScratchpad:switchWorkspaceBehaviorPolicy.scratchpadPresentationStyle(isPhoneIdiom:isPhoneIdiom){"
            )
        )
    }
}

private func workspaceLayoutSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("WorkspaceLayout.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read WorkspaceLayout.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func sidebarSplitViewSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SidebarSplitView.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read SidebarSplitView.swift: \(error)", file: file, line: line)
        throw error
    }
}

private func signedInContentSource(
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sideBarRoot = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = sideBarRoot
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("ContentView+SignedIn.swift")

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read ContentView+SignedIn.swift: \(error)", file: file, line: line)
        throw error
    }
}
