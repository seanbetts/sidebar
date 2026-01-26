//
//  sideBarWidgetsBundle.swift
//  sideBarWidgets
//
//  Created by Sean Betts on 26/01/2026.
//

import SwiftUI
import WidgetKit

@main
struct sideBarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Home screen widgets
        TodayTasksWidget()
        TaskCountWidget()

        // Lock screen widgets
        LockScreenTaskCountWidget()
        LockScreenTaskPreviewWidget()
        LockScreenInlineWidget()
    }
}
