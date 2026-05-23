import XCTest
import sideBarShared

final class WidgetExtensionIconSourceTests: XCTestCase {
    func testWidgetRenderingHelpersRouteSymbolsThroughAppIcon() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
        let widgetLayout = try normalizedSource(at: ["sideBarWidgets", "Widgets", "WidgetListLayout.swift"])
        let emptyState = try normalizedSource(at: ["sideBarWidgets", "Widgets", "WidgetEmptyStateContent.swift"])

        XCTAssertTrue(appIcon.contains("publicstaticletprofileWarning=AppIcon(rawValue:\"person.crop.circle.badge.exclamationmark\")"))
        XCTAssertTrue(appIcon.contains("enumWidget"))
        XCTAssertTrue(appIcon.contains("publicstaticlettaskStack=AppIcon(rawValue:\"square.stack.3d.up\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletuploadFilled=AppIcon(rawValue:\"arrow.up.circle.fill\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletclockFilled=AppIcon(rawValue:\"clock.fill\")"))
        XCTAssertTrue(appIcon.contains("publicstaticletdownloadTrayFilled=AppIcon(rawValue:\"tray.and.arrow.down.fill\")"))

        XCTAssertTrue(widgetLayout.contains("extensionImage{init(appIcon:AppIcon)"))
        XCTAssertTrue(widgetLayout.contains("self.init(systemName:appIcon.rawValue)"))
        XCTAssertTrue(widgetLayout.contains("leticon:AppIcon"))
        XCTAssertTrue(widgetLayout.contains("Image(appIcon:icon)"))
        XCTAssertFalse(widgetLayout.contains("Image(systemName:\"person.crop.circle.badge.exclamationmark\")"))
        XCTAssertFalse(widgetLayout.contains("Image(systemName:iconSystemName)"))

        XCTAssertTrue(emptyState.contains("letappIcon:AppIcon"))
        XCTAssertFalse(emptyState.contains("letsystemImage:String"))
        XCTAssertFalse(emptyState.contains("systemImage:\"pin\""))
    }

    func testWidgetSurfacesUseAppIconAtRenderingBoundaries() throws {
        let files = try normalizedSource(at: ["sideBarWidgets", "Widgets", "PinnedFilesWidget.swift"])
        let notes = try normalizedSource(at: ["sideBarWidgets", "Widgets", "PinnedNotesWidget.swift"])
        let tasks = try normalizedSource(at: ["sideBarWidgets", "Widgets", "TodayTasksWidget.swift"])
        let lockTasks = try normalizedSource(at: ["sideBarWidgets", "Widgets", "LockScreenWidgets.swift"])
        let lockFiles = try normalizedSource(at: ["sideBarWidgets", "Widgets", "LockScreenFilesWidgets.swift"])
        let lockNotes = try normalizedSource(at: ["sideBarWidgets", "Widgets", "LockScreenNotesWidgets.swift"])
        let lockSites = try normalizedSource(at: ["sideBarWidgets", "Widgets", "LockScreenSitesWidgets.swift"])
        let favicons = try normalizedSource(at: ["sideBarWidgets", "Widgets", "WidgetWebsiteFaviconView.swift"])
        let liveActivity = try normalizedSource(
            at: ["sideBarWidgets", "Widgets", "IngestionProgressLiveActivity.swift"]
        )

        XCTAssertTrue(files.contains("privatevarappIcon:AppIcon"))
        XCTAssertTrue(files.contains("Image(appIcon:appIcon)"))
        XCTAssertFalse(files.contains("Image(systemName:iconName)"))

        XCTAssertTrue(notes.contains("Image(appIcon:AppIcon.Content.textDocument)"))
        XCTAssertFalse(notes.contains("Image(systemName:\"doc.text\")"))

        XCTAssertTrue(tasks.contains("Image(appIcon:AppIcon.Action.add)"))
        XCTAssertTrue(tasks.contains("Image(appIcon:AppIcon.State.errorFilled)"))
        XCTAssertTrue(tasks.contains("Image(appIcon:AppIcon.State.success)"))
        XCTAssertTrue(tasks.contains("Image(appIcon:AppIcon.State.emptyCircle)"))
        XCTAssertFalse(tasks.contains("Image(systemName:\"plus\")"))
        XCTAssertFalse(tasks.contains("Image(systemName:\"exclamationmark.circle.fill\")"))

        XCTAssertTrue(lockTasks.contains("Image(appIcon:AppIcon.Tasks.checklist)"))
        XCTAssertTrue(lockTasks.contains("Label("))
        XCTAssertTrue(lockTasks.contains("systemImage:AppIcon.Tasks.checklist.rawValue"))
        XCTAssertFalse(lockTasks.contains("Image(systemName:\"checklist\")"))
        XCTAssertFalse(lockTasks.contains("systemImage:\"checklist\""))

        XCTAssertTrue(lockFiles.contains("Image(appIcon:AppIcon.Content.document)"))
        XCTAssertTrue(lockFiles.contains("systemImage:AppIcon.Content.documentFilled.rawValue"))
        XCTAssertFalse(lockFiles.contains("Image(systemName:\"doc\")"))
        XCTAssertFalse(lockFiles.contains("systemImage:\"doc\""))

        XCTAssertTrue(lockNotes.contains("Image(appIcon:AppIcon.Action.pin)"))
        XCTAssertTrue(lockNotes.contains("Image(appIcon:entry.selection==.all?AppIcon.Widget.pinnedNote:AppIcon.Content.textDocument)"))
        XCTAssertFalse(lockNotes.contains("Image(systemName:\"pin\")"))
        XCTAssertFalse(lockNotes.contains("systemImage:\"pin\""))

        XCTAssertTrue(lockSites.contains("Image(appIcon:AppIcon.Domain.websites)"))
        XCTAssertFalse(lockSites.contains("Image(systemName:\"globe\")"))
        XCTAssertFalse(lockSites.contains("systemImage:\"globe\""))

        XCTAssertTrue(favicons.contains("Image(appIcon:AppIcon.Content.websiteFallback)"))
        XCTAssertFalse(favicons.contains("Image(systemName:\"globe\")"))

        XCTAssertTrue(liveActivity.contains("privatevarbadgeIcon:AppIcon?"))
        XCTAssertTrue(liveActivity.contains("privatevarappIcon:AppIcon?"))
        XCTAssertFalse(liveActivity.contains("Image(systemName:badgeSymbol)"))
        XCTAssertFalse(liveActivity.contains("Image(systemName:symbolName)"))
    }

    func testShareExtensionPlatformImagesUseAppIconAdapters() throws {
        let success = try normalizedSource(at: ["ShareExtension", "ShareSuccessView.swift"])
        let error = try normalizedSource(at: ["ShareExtension", "ShareErrorView.swift"])
        let macState = try normalizedSource(at: ["ShareExtension", "ShareStateView+macOS.swift"])
        let platformHelpers = try normalizedSource(at: ["ShareExtension", "ShareExtensionAppIcon+PlatformImage.swift"])

        XCTAssertTrue(platformHelpers.contains("convenienceinit?(appIcon:AppIcon)"))
        XCTAssertTrue(platformHelpers.contains("self.init(systemName:appIcon.rawValue)"))
        XCTAssertTrue(platformHelpers.contains("self.init(systemSymbolName:appIcon.rawValue"))

        XCTAssertTrue(success.contains("UIImage(appIcon:AppIcon.State.success)"))
        XCTAssertFalse(success.contains("UIImage(systemName:\"checkmark\""))

        XCTAssertTrue(error.contains("UIImage(appIcon:AppIcon.Action.clearFilled)"))
        XCTAssertFalse(error.contains("UIImage(systemName:\"xmark.circle.fill\")"))

        XCTAssertTrue(macState.contains("NSImage(appIcon:AppIcon.Action.clearFilled"))
        XCTAssertTrue(macState.contains("NSImage(appIcon:AppIcon.State.success"))
        XCTAssertFalse(macState.contains("NSImage(systemSymbolName:\"xmark.circle.fill\""))
        XCTAssertFalse(macState.contains("NSImage(systemSymbolName:\"checkmark\""))
    }

    func testWidgetAndShareExtensionProductionFilesAvoidDirectRawSymbolRendering() throws {
        let files = try productionSwiftFiles(under: "sideBarWidgets") + productionSwiftFiles(under: "ShareExtension")
        let rawLiteralPatterns = [
            #"Image\(systemName:\s*""#,
            #"Label\([^\n]*systemImage:\s*""#,
            #"UIImage\(systemName:\s*""#,
            #"NSImage\(systemSymbolName:\s*""#
        ]

        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for pattern in rawLiteralPatterns {
                XCTAssertNil(
                    source.range(of: pattern, options: .regularExpression),
                    "\(fileURL.lastPathComponent) still contains raw symbol rendering matching \(pattern)"
                )
            }
        }
    }

    func testWidgetAppShortcutsUseCompileTimeLiteralIconVocabulary() throws {
        let appIcon = try normalizedSource(at: ["sideBarShared", "Utilities", "AppIcon.swift"])
        let taskIntents = try normalizedSource(at: ["sideBarWidgets", "Intents", "TaskIntents.swift"])
        let shortcutSymbols = [
            ("publicstaticletchecklist=AppIcon(rawValue:\"checklist\")", "checklist"),
            ("publicstaticletaddTaskShortcut=AppIcon(rawValue:\"plus.circle\")", "plus.circle"),
            ("publicstaticlettextDocument=AppIcon(rawValue:\"doc.text\")", "doc.text"),
            ("publicstaticletcreateNoteShortcut=AppIcon(rawValue:\"doc.badge.plus\")", "doc.badge.plus"),
            ("publicstaticletwebsites=AppIcon(rawValue:\"globe\")", "globe"),
            ("publicstaticletdocument=AppIcon(rawValue:\"doc\")", "doc"),
            ("publicstaticletnote=AppIcon(rawValue:\"note.text\")", "note.text"),
            (
                "publicstaticletmessageThread=AppIcon(rawValue:\"bubble.left.and.bubble.right\")",
                "bubble.left.and.bubble.right"
            )
        ]

        for (appIconDefinition, shortcutLiteral) in shortcutSymbols {
            XCTAssertTrue(appIcon.contains(appIconDefinition))
            XCTAssertTrue(taskIntents.contains("systemImageName:\"\(shortcutLiteral)\""))
        }
        XCTAssertFalse(taskIntents.contains("systemImageName:AppIcon."))
    }

    private func normalizedSource(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let source = try source(at: pathComponents, file: file, line: line)
        return source.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private func source(
        at pathComponents: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let sourceURL = rootURL(file: file).appendingPathComponent(pathComponents.joined(separator: "/"))

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(sourceURL.path): \(error)", file: file, line: line)
            throw error
        }
    }

    private func productionSwiftFiles(
        under directory: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [URL] {
        let directoryURL = rootURL(file: file).appendingPathComponent(directory)
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Failed to enumerate \(directoryURL.path)", file: file, line: line)
            return []
        }

        return try enumerator.compactMap { item in
            guard let fileURL = item as? URL, fileURL.pathExtension == "swift" else { return nil }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? fileURL : nil
        }
    }

    private func rootURL(file: StaticString) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
    }

}
