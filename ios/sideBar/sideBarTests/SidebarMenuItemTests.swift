import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class SidebarMenuItemTests: XCTestCase {
    func testDeleteMenuItemUsesSidebarTintPolicyAndDestructiveRole() {
        let item = SidebarMenuItem.delete {}

        XCTAssertEqual(sidebarMenuItemTintPolicy(for: item), .sidebarText)
        XCTAssertEqual(item.role, .destructive)
    }

    func testCopyMenuItemUsesSidebarTextTintPolicy() {
        let item = SidebarMenuItem.copy {}

        XCTAssertEqual(sidebarMenuItemTintPolicy(for: item), .sidebarText)
    }

    func testCopyTranscriptMenuItemFactoryUsesExpectedMetadata() {
        var didInvoke = false
        let item = SidebarMenuItem.copyTranscript {
            didInvoke = true
        }

        XCTAssertEqual(item.title, "Copy Transcript")
        XCTAssertEqual(item.systemImage, "doc.on.doc")
        XCTAssertNil(item.role)

        item.handler()
        XCTAssertTrue(didInvoke)
    }

    func testCopyTextMenuItemFactoryUsesExpectedMetadata() {
        var didInvoke = false
        let item = SidebarMenuItem.copyText {
            didInvoke = true
        }

        XCTAssertEqual(item.title, "Copy Text")
        XCTAssertEqual(item.systemImage, "doc.on.doc")
        XCTAssertNil(item.role)

        item.handler()
        XCTAssertTrue(didInvoke)
    }

    func testShareMenuItemFactoryUsesExpectedMetadata() {
        var didInvoke = false
        let item = SidebarMenuItem.share {
            didInvoke = true
        }

        XCTAssertEqual(item.title, "Share URL")
        XCTAssertEqual(item.systemImage, "square.and.arrow.up.on.square")
        XCTAssertNil(item.role)

        item.handler()
        XCTAssertTrue(didInvoke)
    }

    func testShareTextMenuItemFactoryUsesExpectedMetadata() {
        var didInvoke = false
        let item = SidebarMenuItem.shareText {
            didInvoke = true
        }

        XCTAssertEqual(item.title, "Share Text")
        XCTAssertEqual(item.systemImage, "square.and.arrow.up.on.square")
        XCTAssertNil(item.role)

        item.handler()
        XCTAssertTrue(didInvoke)
    }
}
