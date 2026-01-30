//
//  sideBarWidgetsBundle.swift
//  sideBarWidgets
//
//  Created by Sean Betts on 26/01/2026.
//

import SwiftUI
import WidgetKit

@main
struct SideBarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Home screen widgets - Tasks
        TodayTasksWidget()
        TaskCountWidget()

        // Home screen widgets - Notes
        PinnedNotesWidget()

        // Home screen widgets - Sites
        PinnedSitesWidget()

        // Lock screen widgets - Tasks
        LockScreenTaskCountWidget()
        LockScreenTaskPreviewWidget()
        LockScreenInlineWidget()

        // Lock screen widgets - Notes
        LockScreenNoteCountWidget()
        LockScreenNotePreviewWidget()
        LockScreenNotesInlineWidget()

        // Lock screen widgets - Sites
        LockScreenSiteCountWidget()
        LockScreenSitePreviewWidget()
        LockScreenSitesInlineWidget()
    }
}
