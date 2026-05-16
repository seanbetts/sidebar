# Apple Icon Rationalization

Date: 2026-05-09

Purpose: implementation-facing mapping from current native SF Symbol usage to the target `AppIcon` vocabulary for `RES-MP-13`.

This table does not mean native icon centralization is complete. It records the canonical vocabulary used by the current `AppIcon` catalog and the sidebar, panel, menu action, shared empty/search/status component, feature-level empty-state, task row/detail/modal action/status, task taxonomy/recurrence, compact phone search/action dock, feature search plus Memories/Skills Store chrome, settings/profile chrome, Store Skill credential/config chrome, auth/onboarding chrome, bounded chat/tool/error presentation, and dynamic workspace target/parser presentation slices completed after the initial catalog work.

Categories:

- Canonical: stable sideBar concept, add to `AppIcon`
- Replace: local variation, migrate to a clearer canonical `AppIcon`
- Context-specific: low-frequency but distinct enough to keep
- Dynamic/external: string boundary remains explicit

## Canonical And Context-Specific Mapping

| Current symbol | Concept | Category | Target `AppIcon` | Notes |
|---|---|---|---|---|
| `bubble` | Chat domain | Canonical | `AppIcon.Domain.chat` | Primary chat navigation icon |
| `text.document` | Notes domain | Canonical | `AppIcon.Domain.notes` | Primary notes navigation icon |
| `checkmark.square` | Tasks domain | Canonical | `AppIcon.Domain.tasks` | Primary tasks navigation icon |
| `calendar` | Today task filter and date section | Canonical | `AppIcon.Tasks.today` | Task taxonomy/date affordance |
| `calendar.badge.clock` | Upcoming task filter | Canonical | `AppIcon.Tasks.upcoming` | Task taxonomy/date affordance |
| `calendar.badge.checkmark` | Completed task filter | Canonical | `AppIcon.Tasks.completed` | Task taxonomy/date affordance |
| `square.3.layers.3d` | Task group | Canonical | `AppIcon.Tasks.group` | Task grouping taxonomy |
| `list.bullet` | Task project | Canonical | `AppIcon.Tasks.project` | Task grouping taxonomy |
| `repeat` | Task recurrence | Context-specific | `AppIcon.Tasks.recurrence` | Repeat rule affordance |
| `globe` | Websites domain and website fallback | Canonical | `AppIcon.Domain.websites` / `AppIcon.Content.websiteFallback` | Same raw value, separate semantic aliases |
| `folder` | Files domain, folder content, and new group action | Canonical | `AppIcon.Domain.files` / `AppIcon.Content.folder` | Use the semantic alias that matches the surface |
| `command.circle` | Skills Store and settings skills tab | Canonical | `AppIcon.Domain.skillsStore` / `AppIcon.Settings.skills` | Use the semantic alias that matches the surface |
| `square.grid.2x2` | Settings domain | Canonical | `AppIcon.Domain.settings` | App section icon |
| `bookmark` | Memories | Canonical | `AppIcon.Domain.memories` | Settings memory surfaces |
| `bookmark.fill` | Selected memory | Context-specific | `AppIcon.Domain.memoriesFilled` | Selected Memories row chrome |
| `plus` | Add or create | Canonical | `AppIcon.Action.add` | Header add buttons and add menus |
| `plus.circle.fill` | Add filled circle | Context-specific | `AppIcon.Action.addCircleFilled` | Store Skill install and credential add actions |
| `xmark` | Close or dismiss | Canonical | `AppIcon.Action.close` | Header close buttons and close menu items |
| `xmark.circle` | Cancel in-progress item | Context-specific | `AppIcon.Action.cancel` | Attachment upload cancel control |
| `xmark.circle.fill` | Clear field or filled dismiss | Canonical | `AppIcon.Action.clearFilled` | Search and inline clear controls |
| `ellipsis` | More options | Canonical | `AppIcon.Action.more` | Header menus and overflow actions |
| `trash` | Delete | Canonical | `AppIcon.Action.delete` | Destructive action |
| `trash.circle.fill` | Delete filled circle | Context-specific | `AppIcon.Action.deleteCircleFilled` | Store Skill credential removal action |
| `square.and.arrow.up` | Share file or transcript | Canonical | `AppIcon.Action.share` | Generic share action |
| `square.and.arrow.up.on.square` | Share URL or text | Canonical | `AppIcon.Action.shareOnSquare` | URL/text share affordance |
| `square.and.arrow.down` | Download or export | Canonical | `AppIcon.Action.download` | Downloads and transcript export |
| `doc.on.doc` | Copy | Canonical | `AppIcon.Action.copy` | Generic copy, copy text, markdown, and transcript |
| `textformat` | Copy title | Context-specific | `AppIcon.Action.copyTitle` | Distinguishes title text from generic copy |
| `link` | Copy URL | Context-specific | `AppIcon.Action.copyURL` | Distinguishes URLs from generic copy |
| `pencil` | Rename or edit | Canonical | `AppIcon.Action.rename` | Context menu edit/rename |
| `pencil.circle.fill` | Rename/edit filled circle | Context-specific | `AppIcon.Action.renameCircleFilled` | Store Skill credential update action |
| `square.and.pencil` | Compose | Canonical | `AppIcon.Action.compose` | Compose affordance |
| `arrow.forward.folder` | Move | Canonical | `AppIcon.Action.move` | Move to folder actions |
| `line.3.horizontal` | Reorder | Canonical | `AppIcon.Action.reorder` | Reorder actions |
| `pin` | Pin | Canonical | `AppIcon.Action.pin` | Pin actions |
| `pin.slash` | Unpin | Canonical | `AppIcon.Action.unpin` | Pin inverse |
| `archivebox` | Archive | Canonical | `AppIcon.Action.archive` | Archive actions and archive row header |
| `archivebox.fill` | Unarchive | Canonical | `AppIcon.Action.unarchive` | Archive inverse |
| `magnifyingglass` | Search | Canonical | `AppIcon.Action.search` | Search fields and empty search states |
| `arrow.clockwise` | Refresh or retry | Canonical | `AppIcon.Action.refresh` / `AppIcon.State.retry` | Use action alias for explicit refresh actions, state alias for retry state |
| `arrow.uturn.backward` | Tool undo action | Context-specific | `AppIcon.Action.undo` | Chat tool undo action |
| `arrow.up` | Send | Canonical | `AppIcon.Action.send` | Chat input |
| `paperclip` | Attach | Context-specific | `AppIcon.Action.attach` | Attachment control |
| `arrow.up.right.square` | Open external | Context-specific | `AppIcon.Action.openExternal` | External open action |
| `arrow.up.right` | Onboarding external help | Context-specific | `AppIcon.Onboarding.externalHelp` | Inline help link affordance |
| `rectangle.portrait.and.arrow.right` | Sign out | Context-specific | `AppIcon.Action.signOut` | Account action |
| `chevron.left` | Back | Canonical | `AppIcon.Navigation.back` | Back navigation |
| `chevron.right` | Forward or collapsed disclosure | Canonical | `AppIcon.Navigation.forward` / `AppIcon.Navigation.chevronRight` | Use the semantic alias that matches context |
| `chevron.down` | Expanded disclosure | Canonical | `AppIcon.Navigation.chevronDown` | Expanded archive and disclosure rows |
| `chevron.up.chevron.down` | Picker disclosure | Context-specific | `AppIcon.Navigation.pickerDisclosure` | Form picker affordance |
| `arrow.up.right.and.arrow.down.left` | Expand workspace | Context-specific | `AppIcon.Navigation.expandWorkspace` | Workspace and detail expansion action |
| `arrow.down.left.and.arrow.up.right` | Collapse workspace | Context-specific | `AppIcon.Navigation.collapseWorkspace` | Workspace and detail collapse action |
| `rectangle.on.rectangle` | Workspace surface target | Context-specific | `AppIcon.Workspace.surface` | Inline workspace handoff fallback |
| `arrow.up.forward.app` | Workspace open-entity fallback | Context-specific | `AppIcon.Workspace.openEntityFallback` | Unknown entity fallback |
| `doc.plaintext` | Workspace markdown surface | Context-specific | `AppIcon.Workspace.markdownSurface` | Agent workspace header |
| `tablecells` | Workspace table surface | Context-specific | `AppIcon.Workspace.tableSurface` | Agent workspace header |
| `chart.bar.xaxis` | Workspace chart surface | Context-specific | `AppIcon.Workspace.chartSurface` | Agent workspace header |
| `map` | Workspace map surface | Context-specific | `AppIcon.Workspace.mapSurface` | Agent workspace header |
| `list.bullet.clipboard` | Workspace form surface | Context-specific | `AppIcon.Workspace.formSurface` | Agent workspace header |
| `slider.horizontal.3` | Workspace action-panel surface | Context-specific | `AppIcon.Workspace.actionPanelSurface` | Agent workspace header |
| `checkmark` | Success/check | Canonical | `AppIcon.State.success` | Inline selected checks |
| `checkmark.circle` | Success circle or new task | Canonical | `AppIcon.State.successCircle` | Use for task creation and circular success state |
| `checkmark.circle.fill` | Filled success | Canonical | `AppIcon.State.successFilled` | Filled success indicators |
| `info.circle.fill` | Filled info | Canonical | `AppIcon.State.infoFilled` | Neutral status pill indicator |
| `circle` | Empty circle | Canonical | `AppIcon.State.emptyCircle` | Task checkbox empty state |
| `circle.fill` | Filled circle | Canonical | `AppIcon.State.selectedCircle` | Page dots and selected state |
| `exclamationmark.triangle` | Warning | Canonical | `AppIcon.State.warning` | Non-filled warning |
| `exclamationmark.triangle.fill` | Filled warning | Canonical | `AppIcon.State.warningFilled` | Error banners and ingestion warning |
| `exclamationmark.circle` | Error circle | Canonical | `AppIcon.State.error` | Inline error state |
| `exclamationmark.circle.fill` | Filled error | Canonical | `AppIcon.State.errorFilled` | Filled error state |
| `wifi.slash` | Offline | Canonical | `AppIcon.State.offline` | Offline banner and auth status |
| `wifi.exclamationmark` | Network warning | Canonical | `AppIcon.State.networkWarning` | Degraded network banner |
| `arrow.triangle.2.circlepath` | Syncing | Canonical | `AppIcon.State.syncing` | Queue/sync state |
| `envelope` | Auth email field | Canonical | `AppIcon.Auth.email` | Auth credential field chrome |
| `lock` | Auth password field | Canonical | `AppIcon.Auth.password` | Auth credential field chrome |
| `lock.fill` | Auth password lockout | Context-specific | `AppIcon.Auth.passwordLocked` | Lockout state |
| `eye.fill` | Show password | Context-specific | `AppIcon.Auth.passwordVisible` | Secure field visibility toggle |
| `eye.slash.fill` | Hide password | Context-specific | `AppIcon.Auth.passwordHidden` | Secure field visibility toggle |
| `envelope.badge` | Email verification | Context-specific | `AppIcon.Onboarding.emailVerification` | Onboarding verification step |
| `brain` | Onboarding provider selection | Context-specific | `AppIcon.Onboarding.assistantBrain` | Distinct from filled assistant settings icon |
| `location.fill` | Location permission | Context-specific | `AppIcon.Onboarding.locationPermission` | Onboarding and permission recovery |
| `bell.badge.fill` | Notifications permission | Context-specific | `AppIcon.Onboarding.notificationsPermission` | Onboarding and permission recovery |
| `note.text` | Note document | Canonical | `AppIcon.Content.note` | Note content |
| `doc.text` | Text document | Canonical | `AppIcon.Content.textDocument` | Text document content |
| `doc` | Generic document | Canonical | `AppIcon.Content.document` | File fallback |
| `doc.fill` | Filled document | Context-specific | `AppIcon.Content.documentFilled` | Filled document row |
| `photo` | Image placeholder | Canonical | `AppIcon.Content.photo` | Markdown/image fallback |
| `list.bullet.rectangle` | Task project list | Context-specific | `AppIcon.Content.taskList` | New project action |
| `play.rectangle` | YouTube or video | Canonical | `AppIcon.Media.video` | Video save and YouTube skill |
| `play.circle.fill` | Play filled | Context-specific | `AppIcon.Media.playFilled` | Media viewer |
| `waveform` | Audio waveform | Context-specific | `AppIcon.Media.waveform` | Audio skill |
| `captions.bubble` | Captions/transcript | Context-specific | `AppIcon.Media.captions` | YouTube transcript skill |
| `doc.viewfinder` | PDF page fit | Context-specific | `AppIcon.PDF.fitPage` | PDF controls |
| `plus.magnifyingglass` | Zoom in | Context-specific | `AppIcon.PDF.zoomIn` | PDF controls |
| `minus.magnifyingglass` | Zoom out | Context-specific | `AppIcon.PDF.zoomOut` | PDF controls |
| `distribute.horizontal` | Fit width | Context-specific | `AppIcon.PDF.fitWidth` | PDF controls |
| `distribute.vertical` | Fit height | Context-specific | `AppIcon.PDF.fitHeight` | PDF controls |
| `person.crop.circle` | Profile | Canonical | `AppIcon.Settings.profile` | Profile/account |
| `person.crop.circle.fill` | Filled profile | Context-specific | `AppIcon.Settings.profileFilled` | Profile display |
| `person.crop.circle.badge.plus` | Add profile image | Context-specific | `AppIcon.Settings.profileAdd` | Onboarding profile |
| `person.line.dotted.person` | User settings | Context-specific | `AppIcon.Settings.user` | Settings tab |
| `brain.fill` | Assistant | Canonical | `AppIcon.Settings.assistant` | Settings and calibration |
| `key.horizontal` | Credentials | Context-specific | `AppIcon.Settings.credentials` | Provider key |
| `key.horizontal.fill` | Connected credentials | Context-specific | `AppIcon.Settings.credentialsFilled` | Provider key banner |
| `gearshape` | App preferences | Context-specific | `AppIcon.Settings.appPreferences` | Settings app/general chrome |
| `ellipsis.circle` | More settings tab | Context-specific | `AppIcon.Settings.more` | iOS settings more tab |
| `paintpalette` | Theme | Context-specific | `AppIcon.Settings.theme` | Theme setting |
| `puzzlepiece.extension` | Skill fallback | Canonical | `AppIcon.Skills.fallback` | Unknown skill |
| `tag.fill` | Skill category fallback | Context-specific | `AppIcon.Skills.categoryFallback` | Unknown skill category |
| `hammer` | Skill tools | Context-specific | `AppIcon.Skills.tools` | Tool category |
| `square.stack.3d.up` | Multiple tool or skill summary | Context-specific | `AppIcon.Skills.multiple` | Chat tool summary fallback |
| `person.crop.circle.badge.checkmark` | Assistant identity skill | Context-specific | `AppIcon.Skills.assistantIdentity` | Skill resolver |
| `sparkles` | Assistant soul skill | Context-specific | `AppIcon.Skills.assistantSoul` | Skill resolver |
| `bubble.left.and.bubble.right` | Conversations skill | Context-specific | `AppIcon.Skills.conversations` | Skill resolver |
| `exclamationmark.bubble` | Product feedback skill | Context-specific | `AppIcon.Skills.productFeedback` | Skill resolver |
| `eye` | Prompt preview skill | Context-specific | `AppIcon.Skills.promptPreview` | Skill resolver |
| `gearshape` | Settings/preferences skill | Canonical | `AppIcon.Skills.settingsOtherPreferences` | Skill resolver |
| `shield` | Web crawler policy skill | Context-specific | `AppIcon.Skills.webCrawlerPolicy` | Skill resolver |

## Sidebar, Panel, And Menu Action Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Header overflow menus | `ellipsis` | `HeaderActionMenuButton(icon: AppIcon.Action.more)` or `HeaderActionMenuControl(icon: AppIcon.Action.more)` |
| Header add buttons | `plus` | `HeaderActionButton(icon: AppIcon.Action.add)` |
| Header close buttons | `xmark` | `HeaderActionButton(icon: AppIcon.Action.close)` |
| Workspace refresh menu/action | `arrow.clockwise` | `AppIcon.Action.refresh` through `HeaderActionButton` and `SidebarMenuItem.refresh` |
| Workspace close menu/action | `xmark` | `AppIcon.Action.close` through `HeaderActionButton` and `SidebarMenuItem.close` |
| Notes menus | `pencil`, `arrow.forward.folder`, `doc.on.doc`, `square.and.arrow.up.on.square`, `square.and.arrow.down`, `archivebox`, `trash` | Existing `SidebarMenuItem` factories |
| Files context menu | `square.and.arrow.up` | `SidebarMenuItem.shareFile` |
| Tasks add menu | `checkmark.circle`, `folder`, `list.bullet.rectangle` | `SidebarMenuItem.newTask`, `SidebarMenuItem.newGroup`, `SidebarMenuItem.newProject` |
| Archive section row | `archivebox`, `chevron.down`, `chevron.right` | `AppIcon.Action.archive`, `AppIcon.Navigation.chevronDown`, `AppIcon.Navigation.chevronRight` |
| Workspace expand/collapse | `arrow.up.right.and.arrow.down.left`, `arrow.down.left.and.arrow.up.right` | `AppIcon.Navigation.expandWorkspace`, `AppIcon.Navigation.collapseWorkspace` |

## Shared Empty, Search, And Status Component Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Empty-state content defaults | `magnifyingglass`, `checkmark.circle` | `EmptyStateContent.icon` using `AppIcon.Action.search` and `AppIcon.State.successCircle` |
| Empty-state view rendering | Dynamic `systemImage` boundary | `EmptyStateView.icon` with a string bridge for remaining feature-level call sites |
| Search field | `magnifyingglass`, `xmark.circle.fill` | `AppIcon.Action.search`, `AppIcon.Action.clearFilled` |
| Offline banner | `wifi.slash`, `wifi.exclamationmark` | `AppIcon.State.offline`, `AppIcon.State.networkWarning` |
| Status pill | `info.circle.fill`, `checkmark.circle.fill`, `exclamationmark.triangle.fill` | `AppIcon.State.infoFilled`, `AppIcon.State.successFilled`, `AppIcon.State.warningFilled` |
| Success badge | `checkmark` | `AppIcon.State.success` |

## Feature-Level Empty-State Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Files panel empty state | `folder` | `EmptyStateContent.noContentYet(icon: AppIcon.Domain.files)` |
| Websites panel empty state | `globe` | `EmptyStateContent.noContentYet(icon: AppIcon.Domain.websites)` |
| Notes panel empty state | `text.document` | `EmptyStateContent.noContentYet(icon: AppIcon.Domain.notes)` |
| Conversations panel empty state | `bubble` | `EmptyStateContent.noContentYet(icon: AppIcon.Domain.chat)` |
| Memories empty states | `bookmark` | `EmptyStateView(icon: AppIcon.Domain.memories)` |
| Memories search empty states | `magnifyingglass` | `EmptyStateView(icon: AppIcon.Action.search)` |
| Scratchpad empty state | `square.and.pencil` | `EmptyStateView(icon: AppIcon.Action.compose)` |
| Task selection and completed empty states | `checkmark.circle` | `EmptyStateContent.noSelection(icon: AppIcon.State.successCircle)` and `EmptyStateContent.noContentYet(icon: AppIcon.State.successCircle)` |
| Task upcoming empty state | `calendar` | `EmptyStateContent.noContentYet(icon: AppIcon.Tasks.today)` |

## Task Row, Detail, And Modal Action/Status Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Task row checkbox states | `checkmark`, `circle` | `AppIcon.State.success`, `AppIcon.State.emptyCircle` |
| Task row notes affordance | `text.document` | `AppIcon.Domain.notes` |
| Task overdue indicators | `exclamationmark.circle` | `AppIcon.State.error` |
| Task row delete and overflow actions | `trash`, `ellipsis` | `AppIcon.Action.delete`, `AppIcon.Action.more` |
| Task row move affordance | `folder` | `AppIcon.Content.folder` |
| Task detail add and expand actions | `plus`, `arrow.up.right.and.arrow.down.left`, `arrow.down.left.and.arrow.up.right` | `AppIcon.Action.add`, `AppIcon.Navigation.expandWorkspace`, `AppIcon.Navigation.collapseWorkspace` |
| Task detail success statuses | `checkmark`, `checkmark.circle` | `AppIcon.State.success`, `AppIcon.State.successCircle` |
| Task modal clear and selection states | `xmark.circle.fill`, `checkmark` | `AppIcon.Action.clearFilled`, `AppIcon.State.success` |
| Task panel zero-count status | `checkmark` | `AppIcon.State.success` |

## Task Taxonomy And Recurrence Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Task selection and search headers | `checkmark.square`, `magnifyingglass` | `AppIcon.Domain.tasks`, `AppIcon.Action.search` |
| Task date filters and date sections | `calendar`, `calendar.badge.clock`, `calendar.badge.checkmark` | `AppIcon.Tasks.today`, `AppIcon.Tasks.upcoming`, `AppIcon.Tasks.completed` |
| Task grouping taxonomy | `square.3.layers.3d`, `list.bullet` | `AppIcon.Tasks.group`, `AppIcon.Tasks.project` |
| Task recurrence affordance | `repeat` | `AppIcon.Tasks.recurrence` |

## Compact Phone Search And Action Dock Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Collapsed compact phone search affordance | `magnifyingglass` | `Image(appIcon: AppIcon.Action.search)` |
| Floating add controls and collapsed add menu labels | `plus` | `PhoneFloatingActionButton(icon: AppIcon.Action.add)` and `Image(appIcon: AppIcon.Action.add)` |
| Notes folder creation controls | `folder` | `PhoneFloatingActionButton(icon: AppIcon.Content.folder)` and `Label(..., systemImage: AppIcon.Content.folder.rawValue)` |
| Task quick-create menu item | `checkmark.circle` | `Label(..., systemImage: AppIcon.State.successCircle.rawValue)` |
| Task group and project menu items | `folder`, `list.bullet.rectangle` | `AppIcon.Content.folder` and `AppIcon.Content.taskList` at the SwiftUI `Label` boundary |
| File YouTube action | `play.rectangle` | `PhoneFloatingActionButton(icon: AppIcon.Media.video)` and `Label(..., systemImage: AppIcon.Media.video.rawValue)` |
| Floating action button component | Dynamic `systemName` parameter | `PhoneFloatingActionButton(icon: AppIcon, ...)` |

## Feature Search And Memories/Skills Store Chrome Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Memories search fields | `magnifyingglass`, `xmark.circle.fill` | `Image(appIcon: AppIcon.Action.search)` and `Image(appIcon: AppIcon.Action.clearFilled)` |
| Memories selected row | `bookmark.fill`, `bookmark` | `SettingsMacSkillRow(icon: AppIcon.Domain.memoriesFilled)` and `SettingsMacSkillRow(icon: AppIcon.Domain.memories)` |
| Memories detail placeholder and header | `bookmark` | `PlaceholderView(icon: AppIcon.Domain.memories)` and `Image(appIcon: AppIcon.Domain.memories)` |
| Skills Store content header | `command.circle` | `ContentHeaderRow(icon: AppIcon.Domain.skillsStore)` |
| Skills Store warning and empty-search placeholders | `exclamationmark.triangle`, `magnifyingglass` | `PlaceholderView(icon: AppIcon.State.warning)` and `PlaceholderView(icon: AppIcon.Action.search)` |

## Settings/Profile Chrome Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| iOS settings tabs | `person.crop.circle`, `person.line.dotted.person`, `brain.fill`, `command.circle`, `ellipsis.circle` | `Label(..., systemImage: AppIcon.Settings.*.rawValue)` |
| macOS settings sidebar | `person.crop.circle`, `gearshape`, `person.line.dotted.person`, `brain.fill`, `command.circle`, `bookmark` | `SettingsSection.appIcon` using `AppIcon.Settings.*` and `AppIcon.Domain.memories` |
| Settings modal and form clear controls | `xmark.circle.fill` | `Image(appIcon: AppIcon.Action.clearFilled)` |
| macOS settings disclosure and banners | `chevron.right`, `exclamationmark.triangle.fill`, `info.circle.fill` | `AppIcon.Navigation.chevronRight`, `AppIcon.State.warningFilled`, `AppIcon.State.infoFilled` |
| Profile avatar fallback | `person.crop.circle.fill` | `Image(appIcon: AppIcon.Settings.profileFilled)` |
| More tab destination rows | `bookmark`, `gearshape` | `AppIcon.Domain.memories`, `AppIcon.Settings.appPreferences` |
| Feature chrome helper APIs | Dynamic `systemName` or `iconName` parameters | `ContentHeaderRow(icon:)`, `SettingsMacSkillRow(icon:)`, and `PlaceholderView(icon:)` for migrated call sites |

## Store Skill Credential And Config Chrome Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Store Skill requirements rows | `checkmark.circle` | `Image(appIcon: AppIcon.State.successCircle)` |
| Store Skill provider credential rows | `key`, `key.fill` | `SettingsMacSkillRow(icon: AppIcon.Settings.credentials)` and `SettingsMacSkillRow(icon: AppIcon.Settings.credentialsFilled)` |
| Store Skill credential add/update/remove actions | `plus.circle.fill`, `pencil.circle.fill`, `trash.circle.fill` | `Image(appIcon: AppIcon.Action.addCircleFilled)`, `Image(appIcon: AppIcon.Action.renameCircleFilled)`, and `Image(appIcon: AppIcon.Action.deleteCircleFilled)` |
| Store Skill install/config action pills | `plus.circle.fill`, `checkmark.circle.fill` | `StoreSkillInstallIcon(icon: AppIcon.Action.addCircleFilled)` and `StoreSkillInstallIcon(icon: AppIcon.State.successFilled)` |

## Auth And Onboarding Chrome Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Login email, password, warning, clear, lockout, success, and offline chrome | `envelope`, `lock`, `exclamationmark.triangle.fill`, `xmark.circle.fill`, `lock.fill`, `checkmark.circle.fill`, `wifi.slash` | `AppIcon.Auth.email`, `AppIcon.Auth.password`, `AppIcon.State.warningFilled`, `AppIcon.Action.clearFilled`, `AppIcon.Auth.passwordLocked`, `AppIcon.State.successFilled`, `AppIcon.State.offline` |
| Shared auth secure field visibility controls | `eye.fill`, `eye.slash.fill` | `AppIcon.Auth.passwordVisible`, `AppIcon.Auth.passwordHidden` |
| Password reset and password change field chrome | `lock` | `FormField(leadingIcon: AppIcon.Auth.password)` |
| Onboarding step hero and inline action chrome | `person.crop.circle`, `envelope.badge`, `person.crop.circle.badge.plus`, `brain`, `key.horizontal`, `arrow.up.right`, `location.fill`, `bell.badge.fill`, `checkmark`, `circle.fill`, `chevron.left` | Existing `AppIcon.Settings`, `AppIcon.Onboarding`, `AppIcon.State`, and `AppIcon.Navigation` constants |
| Onboarding discovery feature cards | `text.document`, `checkmark.square`, `globe`, `folder`, `command.circle` | `OnboardingDiscoveryFeature.appIcon` returning `AppIcon.Domain.*` |
| Onboarding permission recovery cards | `location.fill`, `bell.badge.fill` | `OnboardingPermissionRecoveryItem.appIcon` returning `AppIcon.Onboarding.*` |
| Chat add-key banner | `key.horizontal.fill`, `gearshape` | `AppIcon.Settings.credentialsFilled`, `AppIcon.Settings.appPreferences` |

## Bounded Chat, Tool, And Error Presentation Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Chat message copy feedback | `doc.on.doc`, `checkmark.circle` | `AppIcon.Action.copy`, `AppIcon.State.successCircle` |
| Chat stream error pill, retry, and popover | `exclamationmark.triangle.fill`, `arrow.clockwise` | `AppIcon.State.warningFilled`, `AppIcon.State.retry` |
| Active tool banner error state | `exclamationmark.triangle.fill` | `Image(appIcon: AppIcon.State.warningFilled)` |
| Tool action controls | `xmark`, `checkmark`, `arrow.uturn.backward`, `arrow.clockwise` | `AppIcon.Action.close`, `AppIcon.State.success`, `AppIcon.Action.undo`, `AppIcon.State.retry` |
| Tool summary and row icons | `exclamationmark.circle`, `square.stack.3d.up`, `checkmark.circle.fill` | `AppIcon.State.error`, `AppIcon.Skills.multiple`, `AppIcon.State.successFilled` |
| Skill icon wrapper in touched tool surfaces | Resolved `systemName` strings | `SkillIconResolver.appIcon(for:)` rendered through `SkillSymbolIcon(appIcon:)` |

## Dynamic Workspace Target And Parser Presentation Slice

| Surface | Former direct symbols | Target |
|---|---|---|
| Workspace surface parser fallback | `rectangle.on.rectangle` | `AppIcon.Workspace.surface` on `ToolResultWorkspaceSurfaceTarget.appIcon` |
| Tool-originated workspace targets | Skill resolver string names | `SkillIconResolver.appIcon(for:)` assigned to parser targets |
| Open note entity target | `doc.text` | `AppIcon.Content.textDocument` |
| Open website entity target | `globe` | `AppIcon.Domain.websites` |
| Open file entity target | `folder` | `AppIcon.Domain.files` |
| Open conversation entity target | `bubble.left` | `AppIcon.Domain.chat`, consolidating on the canonical chat icon |
| Open scratchpad entity target | `square.and.pencil` | `AppIcon.Action.compose` |
| Open task entity targets | `checkmark.square` | `AppIcon.Domain.tasks` |
| Unknown open-entity fallback | `arrow.up.forward.app` | `AppIcon.Workspace.openEntityFallback` |
| Agent workspace surface headers | `doc.plaintext`, `tablecells`, `chart.bar.xaxis`, `map`, `list.bullet.clipboard`, `slider.horizontal.3` | `AppIcon.Workspace.*Surface` values through `ContentHeaderRow(icon:)` |
| Inline workspace action labels | Target-owned `iconName` strings | SwiftUI `Label(..., systemImage: target.appIcon.rawValue)` at the rendering boundary |

## Chat Input And Attachment Controls Slice

Completed on `2026-05-16` as a bounded `RES-MP-13` slice.

| Surface | Prior direct symbol use | Canonical target |
|---|---|---|
| iOS chat input attach button | `paperclip` through `UIImage(systemName:)` | `AppIcon.Action.attach` through `makeAccessoryButton(appIcon:)` |
| iOS chat input send button | `arrow.up` through `UIImage(systemName:)` | `AppIcon.Action.send` through `makeAccessoryButton(appIcon:)` |
| macOS chat input attach button | `paperclip` through `NSImage(systemSymbolName:)` | `AppIcon.Action.attach` through `symbolImage(for:)` |
| macOS chat input send button | `arrow.up` through `NSImage(systemSymbolName:)` | `AppIcon.Action.send` through `symbolImage(for:)` |
| Pending attachment row icon | `paperclip` | `AppIcon.Action.attach` |
| Attachment retry action | `arrow.clockwise` | `AppIcon.State.retry` |
| Attachment delete action | `trash` | `AppIcon.Action.delete` |
| Attachment cancel action | `xmark.circle` | `AppIcon.Action.cancel` |
| Ready attachment chip icon | `paperclip` | `AppIcon.Action.attach` |
| Ready attachment remove action | `xmark` | `AppIcon.Action.close` |

## Explicit Later Boundaries

The following direct symbol areas remain tracked under `RES-MP-13` for later slices:

- widgets and extensions
- PDF controls
- non-menu feature view icons outside the completed compact phone search/action dock, feature search plus Memories/Skills Store chrome, settings/profile chrome, Store Skill credential/config chrome, auth/onboarding chrome, bounded chat/tool/error presentation, dynamic workspace target/parser presentation, and chat input plus attachment control slices
- dynamic/external symbol payloads
- the production-wide strict source guard
