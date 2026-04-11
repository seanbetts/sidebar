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

    func testCopyTitleMenuItemFactoryUsesExpectedMetadata() {
        var didInvoke = false
        let item = SidebarMenuItem.copyTitle {
            didInvoke = true
        }

        XCTAssertEqual(item.title, "Copy Title")
        XCTAssertEqual(item.systemImage, "textformat")
        XCTAssertNil(item.role)

        item.handler()
        XCTAssertTrue(didInvoke)
    }

    func testCopyURLMenuItemFactoryUsesExpectedMetadata() {
        var didInvoke = false
        let item = SidebarMenuItem.copyURL {
            didInvoke = true
        }

        XCTAssertEqual(item.title, "Copy URL")
        XCTAssertEqual(item.systemImage, "link")
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

    func testWebsiteMenuSourcesUseSharedCopyTitleAndCopyURLFactories() throws {
        let detailNormalized = try websitesSource(named: "WebsitesDetailView+MenuActions.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let listNormalized = try websitesSource(named: "WebsitesView.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let panelNormalized = try sidebarPanelSource(named: "WebsitesPanel+ContextMenu.swift")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(detailNormalized.contains(".copyTitle{copyWebsiteTitle()}"))
        XCTAssertTrue(detailNormalized.contains(".copyURL{copyWebsiteURL()}"))
        XCTAssertFalse(detailNormalized.contains("SidebarMenuItem(title:\"CopyTitle\""))
        XCTAssertFalse(detailNormalized.contains("SidebarMenuItem(title:\"CopyURL\""))

        XCTAssertTrue(listNormalized.contains(".copyTitle{copyWebsiteTitle()}"))
        XCTAssertTrue(listNormalized.contains(".copyURL{copyWebsiteURL()}"))
        XCTAssertFalse(listNormalized.contains("SidebarMenuItem(title:\"CopyTitle\""))
        XCTAssertFalse(listNormalized.contains("SidebarMenuItem(title:\"CopyURL\""))

        XCTAssertTrue(panelNormalized.contains(".copyTitle{copyWebsiteTitle(for:item)}"))
        XCTAssertTrue(panelNormalized.contains(".copyURL{copyWebsiteURL(for:item)}"))
        XCTAssertFalse(panelNormalized.contains("SidebarMenuItem(title:\"CopyTitle\""))
        XCTAssertFalse(panelNormalized.contains("SidebarMenuItem(title:\"CopyURL\""))
    }
}

private func websitesSource(
    named fileName: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("Websites")
        .appendingPathComponent(fileName)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(fileName): \(error)", file: file, line: line)
        throw error
    }
}

private func sidebarPanelSource(
    named fileName: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    let fileURL = URL(fileURLWithPath: "\(file)")
    let sourceURL = fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sideBar")
        .appendingPathComponent("Views")
        .appendingPathComponent("SidebarPanels")
        .appendingPathComponent(fileName)

    do {
        return try String(contentsOf: sourceURL, encoding: .utf8)
    } catch {
        XCTFail("Failed to read \(fileName): \(error)", file: file, line: line)
        throw error
    }
}
