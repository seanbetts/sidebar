# Apple Icon Inventory

Date: 2026-05-04

Scope: production Swift under `ios/sideBar`, excluding tests, build output, and vendored code. This includes the main iOS/macOS app, widgets, and share extension code.

Follow-up rationalization table: [Apple Icon Rationalization](./apple-icon-rationalization-2026-05-09).

## Summary

- Production Swift files scanned: 778
- Direct SF Symbol literal call or argument occurrences: 287
- Unique direct SF Symbols: 85
- Icon-oriented literal occurrences, including existing providers and indirect `iconName` values: 649
- Unique icon-oriented SF Symbols: 111
- Non-SF image assets used as icons or logos: `AppLogo`, `ProviderAnthropicLogo`, `ProviderGoogleLogo`, `ProviderOpenAILogo`, `LargeIcon`, `AppIcon`

## Existing Indirection

The app already has several partial icon providers:

- `ios/sideBar/sideBar/Models/AppSection.swift`: app section icons for chat, notes, files, websites, skills store, settings, and tasks.
- `ios/sideBar/sideBar/Utilities/SkillIconResolver.swift`: skill and tool-call icon resolution.
- `ios/sideBar/sideBar/Design/Components/SidebarMenuItem.swift`: common context menu action icons.
- `ios/sideBar/sideBar/Design/Components/HeaderActionIcon.swift`: common rendering for header action symbols, but accepts raw strings.
- `ios/sideBar/sideBar/Design/Components/EmptyStateContent.swift`: common empty-state icons.
- `ios/sideBar/sideBar/Views/SkillsStore/SkillsStoreCardComponents.swift`: category icons for the skills store.
- `ios/sideBar/sideBar/Views/Settings/SettingsView.swift` and `SettingsMoreTabView.swift`: settings section icons.
- Widget models pass `emptyStateSystemImage` through to widget views.

## Direct SF Symbol Use

Direct uses by area:

| Area | Direct occurrences |
| --- | ---: |
| Main app | 250 |
| Widgets | 33 |
| Share extension | 4 |

Most repeated direct symbols:

| Symbol | Direct occurrences |
| --- | ---: |
| `plus` | 32 |
| `ellipsis` | 17 |
| `checkmark` | 15 |
| `xmark.circle.fill` | 14 |
| `checkmark.circle` | 12 |
| `folder` | 11 |
| `xmark` | 11 |
| `globe` | 9 |
| `magnifyingglass` | 8 |
| `exclamationmark.triangle.fill` | 7 |
| `doc.on.doc` | 5 |
| `square.and.arrow.down` | 5 |
| `trash` | 5 |
| `bookmark` | 5 |
| `square.and.arrow.up` | 5 |
| `textformat` | 4 |
| `chevron.left` | 4 |
| `list.bullet.rectangle` | 4 |
| `play.rectangle` | 4 |
| `checklist` | 4 |

Highest-volume files for direct literals:

| File | Direct occurrences |
| --- | ---: |
| `ios/sideBar/sideBar/Views/ContentView+CompactPhoneSearchDock.swift` | 15 |
| `ios/sideBar/sideBar/Views/Files/PDFControlBar.swift` | 14 |
| `ios/sideBar/sideBar/Design/Components/SidebarMenuItem.swift` | 13 |
| `ios/sideBar/sideBar/Views/ContentView+Layout.swift` | 11 |
| `ios/sideBar/sideBar/Views/Notes/NotesDetailView+MenuActions.swift` | 11 |
| `ios/sideBar/sideBar/Views/Settings/MemoriesSettingsView.swift` | 9 |
| `ios/sideBar/sideBar/Views/Tasks/TasksViewComponents.swift` | 9 |
| `ios/sideBar/sideBar/Views/Chat/ChatHeaderView.swift` | 9 |
| `ios/sideBar/sideBar/Views/SidebarPanels/TasksPanel+AddMenu.swift` | 8 |
| `ios/sideBar/sideBarWidgets/Widgets/TodayTasksWidget.swift` | 7 |

## Full Symbol Inventory

This list includes direct SF Symbol literals plus icon-oriented literals in existing providers, `iconName` values, and computed icon returns:

`archivebox`, `arrow.clockwise`, `arrow.counterclockwise.circle`, `arrow.forward.folder`, `arrow.left.arrow.right`, `arrow.triangle.2.circlepath`, `arrow.up`, `arrow.up.circle.fill`, `arrow.up.right`, `arrow.up.right.square`, `bell.badge.fill`, `bookmark`, `brain`, `brain.fill`, `bubble`, `bubble.left.and.bubble.right`, `calendar`, `calendar.badge.checkmark`, `calendar.badge.clock`, `captions.bubble`, `checklist`, `checkmark`, `checkmark.circle`, `checkmark.circle.fill`, `checkmark.square`, `chevron.left`, `chevron.right`, `chevron.up.chevron.down`, `circle`, `circle.fill`, `clock.fill`, `command.circle`, `distribute.horizontal`, `distribute.vertical`, `doc`, `doc.fill`, `doc.on.doc`, `doc.text`, `doc.viewfinder`, `ellipsis`, `ellipsis.circle`, `envelope.badge`, `exclamationmark`, `exclamationmark.bubble`, `exclamationmark.circle`, `exclamationmark.circle.fill`, `exclamationmark.triangle`, `exclamationmark.triangle.fill`, `eye`, `folder`, `gearshape`, `gearshape.fill`, `globe`, `hammer`, `icloud.and.arrow.up`, `key.horizontal`, `key.horizontal.fill`, `line.3.horizontal`, `line.3.horizontal.decrease.circle`, `link`, `list.bullet`, `list.bullet.rectangle`, `location.fill`, `lock.fill`, `magnifyingglass`, `minus`, `minus.magnifyingglass`, `note.text`, `paperclip`, `pencil`, `pencil.circle.fill`, `pencil.line`, `person.crop.circle`, `person.crop.circle.badge.checkmark`, `person.crop.circle.badge.exclamationmark`, `person.crop.circle.badge.plus`, `person.crop.circle.fill`, `person.line.dotted.person`, `photo`, `pin`, `play.circle.fill`, `play.rectangle`, `plus`, `plus.circle.fill`, `plus.magnifyingglass`, `puzzlepiece.extension`, `rectangle.on.rectangle`, `repeat`, `shield`, `sparkles`, `sparkles.rectangle.stack`, `square.3.layers.3d`, `square.and.arrow.down`, `square.and.arrow.up`, `square.and.arrow.up.on.square`, `square.and.pencil`, `square.grid.2x2`, `square.stack.3d.up`, `tag.fill`, `text.document`, `textformat`, `trash`, `trash.circle.fill`, `tray`, `tray.and.arrow.down.fill`, `waveform`, `wifi.exclamationmark`, `wifi.slash`, `xmark`, `xmark.circle`, `xmark.circle.fill`

## Direct Symbol Inventory

These are the 85 symbols passed directly as `systemName`, `systemImage`, or `systemSymbolName` literals:

`archivebox`, `arrow.clockwise`, `arrow.counterclockwise.circle`, `arrow.forward.folder`, `arrow.left.arrow.right`, `arrow.triangle.2.circlepath`, `arrow.up`, `arrow.up.right`, `arrow.up.right.square`, `bell.badge.fill`, `bookmark`, `brain`, `brain.fill`, `bubble`, `calendar`, `checklist`, `checkmark`, `checkmark.circle`, `checkmark.circle.fill`, `chevron.left`, `chevron.right`, `chevron.up.chevron.down`, `circle`, `circle.fill`, `command.circle`, `distribute.horizontal`, `distribute.vertical`, `doc`, `doc.fill`, `doc.on.doc`, `doc.text`, `doc.viewfinder`, `ellipsis`, `ellipsis.circle`, `envelope.badge`, `exclamationmark`, `exclamationmark.circle`, `exclamationmark.circle.fill`, `exclamationmark.triangle.fill`, `folder`, `gearshape`, `globe`, `key.horizontal`, `key.horizontal.fill`, `line.3.horizontal`, `line.3.horizontal.decrease.circle`, `link`, `list.bullet`, `list.bullet.rectangle`, `location.fill`, `lock.fill`, `magnifyingglass`, `minus`, `minus.magnifyingglass`, `paperclip`, `pencil`, `person.crop.circle`, `person.crop.circle.badge.exclamationmark`, `person.crop.circle.badge.plus`, `person.crop.circle.fill`, `person.line.dotted.person`, `photo`, `pin`, `play.circle.fill`, `play.rectangle`, `plus`, `plus.circle.fill`, `plus.magnifyingglass`, `repeat`, `sparkles.rectangle.stack`, `square.and.arrow.down`, `square.and.arrow.up`, `square.and.arrow.up.on.square`, `square.and.pencil`, `square.stack.3d.up`, `text.document`, `textformat`, `trash`, `trash.circle.fill`, `tray`, `wifi.exclamationmark`, `wifi.slash`, `xmark`, `xmark.circle`, `xmark.circle.fill`

## Centralization Notes

- A flat dictionary would reduce string duplication, but a semantic API is likely safer than exposing raw dictionary keys everywhere.
- The existing shape points toward a central `AppIcon` or `SidebarSymbol` namespace with semantic constants, plus domain-specific resolvers for app sections, skills, menu actions, empty states, task states, file states, and widget states.
- The highest-value first pass is replacing generic repeated actions and navigation symbols: add, close, more, delete, share, download, copy, folder, search, checkmark, error, warning, website, notes, tasks, files.
- `SkillIconResolver`, `AppSection.iconName`, and `SidebarMenuItem` should become clients of the central icon namespace rather than being deleted. Their semantic mapping responsibilities are still useful.
- UIKit/AppKit bridge points need helper accessors as well as SwiftUI string values, since the share extension, chat input, note formatting bar, and PDF controls create `UIImage` or `NSImage` from symbol names.

## Extraction Commands

Primary direct literal search:

```bash
rg -n --pcre2 'systemName:\s*"[^"]+"|systemImage:\s*"[^"]+"|systemSymbolName:\s*"[^"]+"|UIImage\(systemName:\s*"[^"]+"|NSImage\(systemSymbolName:\s*"[^"]+"' ios/sideBar -g '*.swift' -g '!**/*Tests/**' -g '!**/*UITests/**'
```

Broader icon-oriented search:

```bash
rg -n --pcre2 '(iconName|systemImage|systemName|symbolName|badgeSymbol|emptyStateSystemImage|leadingSystemImage|trailingDeleteSystemImage)\s*[:=]\s*"[^"]+"' ios/sideBar -g '*.swift' -g '!**/*Tests/**' -g '!**/*UITests/**'
```
