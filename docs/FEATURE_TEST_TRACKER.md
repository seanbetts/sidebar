# iOS/macOS Feature Test Tracker

Single-file source of truth for Apple-platform feature coverage.

## Status Legend

- `Covered`: automated tests exist and run in CI for the intended level.
- `Partial`: some automation exists, but key paths or UI journeys are still missing.
- `Planned`: not automated yet.

## Feature Matrix

| Area | Feature ID | Feature | Risk | Current Coverage | Linked Automated Tests | Seed Profile | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Auth | AUTH-001 | Email/password sign-in | High | Unit + integration + UI deterministic | `SupabaseAuthAdapterTests`, `KeychainAuthStateStoreTests`, `TC-UI-001`, `TC-UI-002` | `clean_user` | Covered |
| Auth | AUTH-002 | Session restore + biometric lock | High | Unit | `AuthStateStore` tests, `BiometricMonitor` paths | `clean_user` | Planned |
| Chat | CHAT-001 | Send message in existing conversation | High | Unit + integration + UI deterministic | `ChatViewModelTests`, `ChatStoreTests`, `ChatAPITests`, `TC-UI-003` | `seeded_user` | Partial |
| Chat | CHAT-002 | Streaming response lifecycle | High | Unit + integration + UI deterministic | `ChatStreamParserTests`, `URLSessionChatStreamClientTests`, `TC-UI-003` | `seeded_user` | Partial |
| Notes | NOTE-001 | Notes create/edit/delete | High | Unit + integration + UI deterministic | `NotesViewModelTests`, `NotesStoreTests`, `NotesAPITests`, `TC-UI-004` | `seeded_user` | Partial |
| Notes | NOTE-002 | Editor formatting + markdown behavior | Medium | Unit | `NotesEditorViewModelTests`, `NativeMarkdownEditorViewModelTests` | `seeded_user` | Partial |
| Files | FILE-001 | Local file upload flow | High | Unit + integration | `IngestionUploadManagerTests`, `IngestionStoreTests`, `FilesAPITests` | `seeded_user` + upload fixtures | Partial |
| Files | FILE-002 | Upload polling, retry, and failure states | High | Unit | `IngestionViewModelTests`, `IngestionViewModelPollingStressTests` | `seeded_user` + upload fixtures | Partial |
| Tasks | TASK-001 | Task CRUD in inbox/list views | High | Unit + integration | `TasksViewModelTests`, `TasksStoreTests`, `TasksAPITests` | `seeded_user` | Partial |
| Tasks | TASK-002 | Scheduling/repeating/completion states | High | Unit | `TaskManagerTests`, `TasksUtilsTests` | `seeded_user` (overdue/someday/completed) | Partial |
| Websites | WEB-001 | Save/list/read websites | Medium | Unit + integration | `WebsitesViewModelTests`, `WebsitesStoreTests`, `WebsitesAPITests` | `seeded_user` | Partial |
| Sync | SYNC-001 | Offline writes + reconnect reconciliation | High | Unit + integration | `OfflineStoreTests`, `WriteQueueTests`, `SyncCoordinatorTests` | `seeded_user` | Partial |
| Realtime | RT-001 | Realtime event mapping and apply | Medium | Unit | `SupabaseRealtimeAdapterTests`, `RealtimeMappersTests` | `seeded_user` | Partial |
| Settings | SET-001 | Settings fetch/update + app config | Medium | Unit + integration | `SettingsViewModelTests`, `SettingsAPITests`, `EnvironmentConfigLoadTests` | `seeded_user` | Partial |
| Share Extension | EXT-SHARE-001 | Share extension queue contract | High | Unit | `ShareExtensionQueueContractTests`, `PendingShareStoreTests` | `seeded_user` | Partial |
| Widgets | EXT-WIDGET-001 | Widget data model/provider behavior | Medium | Unit | `WidgetModelConversionTests`, `WidgetBridgeContractTests` | `seeded_user` | Partial |
| Safari Extension | EXT-SAFARI-001 | Safari message/deeplink handling | Medium | Unit | `SafariExtensionMessageHandlerTests` | `seeded_user` | Partial |
| Shell | UI-001 | App launch + navigation shell | High | UI smoke + `TC-UI-001` login success | `sideBarUITests`, `sideBarUITestsLaunchTests` | `clean_user` | Partial |
| Workspace | WS-001 | Parse and apply AI workspace patch events | High | Unit | `ChatWorkspacePatchParserTests`, `WorkspaceStoreTests`, `WorkspaceModelsAgentSurfaceTests` | `seeded_user` | Covered |
| Workspace | WS-002 | Assistant surface title-bar menu actions (copy/share/download) | Medium | Unit | `ToolResultWorkspaceSurfaceParserTests`, `PromptPreviewWorkspaceSurfaceFactoryTests` | `seeded_user` | Partial |
| Workspace | WS-003 | Reopen assistant surface from chat tool bubble action | High | Unit + UI deterministic | `ToolResultWorkspaceSurfaceParserTests` + pending UI journey (`TC-UI-013`) | `seeded_user` | Partial |
| Workspace | WS-004 | Keyboard and pane parity for assistant surfaces (Esc close, expand/swap) | High | Unit + manual checkpoint coverage | `WorkspaceStoreTests`, `WorkspaceLegacySectionAdapterTests` | `seeded_user` | Partial |

## UI Journey Cases (Deterministic)

Target: at least 12 stable UI journeys in CI.

| TC ID | Journey | Covers | Priority | State |
| --- | --- | --- | --- | --- |
| TC-UI-001 | Login success to signed-in home | `AUTH-001`, `UI-001` | P0 | Covered |
| TC-UI-002 | Login failure shows deterministic error | `AUTH-001` | P0 | Covered |
| TC-UI-003 | Send chat message and receive streamed reply | `CHAT-001`, `CHAT-002` | P0 | Covered |
| TC-UI-004 | Create/edit/delete note | `NOTE-001` | P0 | Covered |
| TC-UI-005 | Upload local file and reach processed state | `FILE-001`, `FILE-002` | P0 | Planned |
| TC-UI-006 | Create task, complete task, verify filters | `TASK-001`, `TASK-002` | P0 | Planned |
| TC-UI-007 | Overdue/someday/completed lanes render correctly | `TASK-002` | P1 | Planned |
| TC-UI-008 | Save website and verify detail rendering | `WEB-001` | P1 | Planned |
| TC-UI-009 | Offline note edit then reconnect sync | `SYNC-001` | P0 | Planned |
| TC-UI-010 | Offline task create then reconnect sync | `SYNC-001`, `TASK-001` | P0 | Planned |
| TC-UI-011 | Share extension handoff appears in app | `EXT-SHARE-001`, `FILE-001` | P1 | Planned |
| TC-UI-012 | Settings update persists after relaunch | `SET-001` | P1 | Planned |
| TC-UI-013 | Prompt preview shows "Show System Prompt" and reopens assistant workspace | `WS-003`, `CHAT-002` | P0 | Planned |
| TC-UI-014 | Assistant workspace header `...` menu executes copy/share/download actions | `WS-002` | P1 | Planned |
| TC-UI-015 | Escape key closes assistant workspace surface in focused pane | `WS-004` | P1 | Planned |
| TC-UI-016 | iPad rotate/expand and pane swap preserve assistant surface state | `WS-004` | P1 | Planned |

## Backlog (Next 6)

- [ ] Implement `TC-UI-005` using local upload fixtures.
- [ ] Implement `TC-UI-006` against seeded overdue/someday/completed task states.
- [ ] Implement `TC-UI-009` by forcing network off/on during note edit flow.
- [ ] Implement `TC-UI-008` for end-to-end website save and detail rendering.
- [ ] Implement `TC-UI-010` for deterministic offline task create/reconnect sync.
- [ ] Implement `TC-UI-013` for chat-to-assistant-surface reopen flow.

## How To Add New Features

1. Add one row in `Feature Matrix` with a new `Feature ID` under the correct `Area`.
2. Add or link at least one `TC-UI-*` journey if feature risk is `High`.
3. Update `Status` to `Covered` only when the automated test is committed and running in CI.
4. Keep seed requirements explicit in `Seed Profile` so test setup stays repeatable.
