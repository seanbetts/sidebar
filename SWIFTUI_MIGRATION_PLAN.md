# SwiftUI Universal App Migration Plan

## Executive Summary

Based on comprehensive analysis of the SvelteKit frontend, this document outlines a detailed roadmap for building a universal macOS/iOS/iPadOS app with native UX and capability parity. This plan assumes an architect/director role working with an AI coding agent.

### Native-First Design Principles (Non-Negotiable)

This app should feel like a first-class Apple platform app, not a web replica. These principles supersede web parity when they conflict.

1. **Native UI over web mimicry**
   - Use SwiftUI patterns, Apple HIG navigation, and platform conventions.
   - macOS: toolbar + sidebar + multiwindow; iOS: tab or split layouts; iPad: 2-3 column layouts.
2. **Prefer native APIs when available**
   - Use platform frameworks (PDFKit, AVFoundation, Quick Look, CoreLocation, etc.).
   - For Things, use native APIs (no bridge dependency in SwiftUI).
3. **Backend as sync source, not UX driver**
   - The backend enables data sync and AI capabilities, but the UX should be built for native behaviors.
4. **Platform-specific UX is expected**
   - Embrace differences: context menus, keyboard shortcuts, windowing, drag/drop, and multi-pane navigation.
5. **Design for offline reading and fast local interactions**
   - Cache first, revalidate in background, and show native loading states.

---

## Addendum: Codebase Parity Gaps (Jan 2026 Review)

The current app includes additional features and data-flow specifics that are not called out in the original plan. To achieve true parity, incorporate the following:

### 1) Things Integration (Mac-Only Bridge)
- Add a dedicated phase (or extend Phase 7) for Things tasks.
- Feature scope: list tasks, filter views (today/upcoming/area/project/search), task actions (rename, move, defer, due date, delete), and bridge status/installation UI.
- Note: The bridge runs on macOS and requires bearer token auth; iOS/iPadOS should surface read-only or "bridge unavailable" messaging.

### 1a) Native Things Integration (SwiftUI) and Future Migration
- The SwiftUI app can integrate directly with Things on macOS/iOS using native APIs, separate from the existing bridge.
- Treat the current bridge as web-only legacy; SwiftUI should not depend on it.
- Plan a later transition to an in-app todo system once SwiftUI is stable; design the SwiftUI task layer behind an interface so swapping the backend is low-impact.

### 1b) Task System Architecture (for Future Migration)
- Define a TaskProvider interface in Swift (list, search, create, update, delete, defer, move, set due).
- Implement a ThingsTaskProvider first, backed by native Things APIs.
- Add an InAppTaskProvider later, backed by sideBar storage and API services.
- Keep view models unaware of concrete provider details (dependency injection).
- Plan for a one-time import flow from Things into the in-app model.

### 2) Skills Management in Settings
- Add Skills section in Settings (view available skills, enable/disable list).
- Mirrors existing Settings capability and supports tool filtering in chat.

### 3) Scratchpad Implementation Detail
- Scratchpad is backed by a special note title and realtime updates.
- iOS should follow the same mapping (no separate scratchpad entity).

### 4) Files: Workspace vs Ingestion
- Split file features into two tracks:
  - Workspace files: tree browsing + file operations (rename, move, delete).
  - Ingestion files: upload processing status, pinned order, and viewer state.
- UI should reflect ingestion job status and allow viewing processed content.

### 5) SSE Event Coverage Beyond Tokens
- The chat SSE stream emits UI events beyond tokens and tool calls:
  - note_created, note_updated, note_deleted
  - website_saved, website_deleted
  - ui_theme_set
  - scratchpad_updated, scratchpad_cleared
  - prompt_preview
  - tool_start, tool_end
- iOS should handle these to stay in sync with existing behavior.

These gaps are additive and do not change the MVP-first strategy, but they should be scheduled into the relevant phases to avoid late-stage parity surprises.

### Delivery Strategy: MVP-First Approach

**This plan uses a two-phase delivery strategy:**

**Phase I - Read-Only MVP** (Recommended First)
- Focus on viewing capabilities across all content types
- Defer editing features (markdown editor, chat input, content creation)
- Deliver a functional, useful app in 7-11 weeks
- Validate architecture and foundations before tackling complex editing

**Phase II - Editing Capabilities** (Post-MVP)
- Add chat input and message sending
- Build full markdown editor with formatting toolbar
- Enable note creation and editing
- Complete capability parity with native UX

### Effort Estimates

**Read-Only MVP:**
- **Sessions**: 22-33 (vs 36-51 for full app)
- **Hours**: 88-132 hours (vs 157-280 for full app)
- **Timeline**: 7-11 weeks at 3-4 sessions per week
- **Complexity**: Medium (defers hardest 40% of work)

**Full App (MVP + Editing):**
- **Sessions**: 36-51 total
- **Hours**: 157-280 hours total
- **Timeline**: 12-18 weeks total
- **Complexity**: High (native markdown editor and streaming)

---

## Progress Tracker

### Overall Progress

**Current Target**: Read-Only MVP
**Status**: Not Started
**Sessions Completed**: 0 / 22-33 (MVP) or 0 / 36-51 (Full App)
**Hours Logged**: 0 / 88-132 (MVP) or 0 / 157-280 (Full App)
**Weeks Elapsed**: 0 / 7-11 (MVP) or 0 / 12-18 (Full App)

```
MVP Progress:      [░░░░░░░░░░░░░░░░░░░░] 0%
Full App Progress: [░░░░░░░░░░░░░░░░░░░░] 0%

Critical Path (MVP): [░░░░░░░░░░░░░░░░░░░░] 0%
(Phases 1 → 2 → 3-Modified → 4-Reduced → 5 → 6-Modified → 7-Modified → 8 → 9)
```

### Phase Completion Status

#### Read-Only MVP Phases

| Phase | Status | Sessions (MVP) | Sessions (Full) | Complete | MVP Scope |
|-------|--------|----------------|-----------------|----------|-----------|
| **1. Foundation & Architecture** | ⬜ Not Started | 0 / 3-4 | 0 / 3-4 | 0% | Full |
| **2. Navigation & Layout** | ⬜ Not Started | 0 / 3-4 | 0 / 3-4 | 0% | Full |
| **3. Chat Viewer** | ⬜ Not Started | 0 / 4-5 | 0 / 5-7 | 0% | Modified (no input) |
| **4. Note Viewer** | ⬜ Not Started | 0 / 2-3 | 0 / 7-10 | 0% | Heavily Reduced (read-only) |
| **5. File Viewing** | ⬜ Not Started | 0 / 4-6 | 0 / 4-6 | 0% | Full (already read-only) |
| **6. Website Viewer** | ⬜ Not Started | 0 / 1-2 | 0 / 2-3 | 0% | Modified (no saving) |
| **7. Additional Features** | ⬜ Not Started | 0 / 2-3 | 0 / 3-4 | 0% | Modified (view-only) |
| **8. Platform Optimization** | ⬜ Not Started | 0 / 5-7 | 0 / 5-7 | 0% | Full |
| **9. MVP Testing** | ⬜ Not Started | 0 / 3-4 | 0 / 4-6 | 0% | Modified (read-only testing) |
| **MVP TOTAL** | | **22-33** | | | |

#### Post-MVP: Editing Capabilities (Phase 10)

| Phase | Status | Sessions | Complete | Full App Required |
|-------|--------|----------|----------|-------------------|
| **10.1 Chat Input** | ⬜ Not Started | 0 / 2-3 | 0% | ✅ Yes |
| **10.2 Markdown Editor** | ⬜ Not Started | 0 / 6-9 | 0% | ✅ Yes |
| **10.3 Note Operations** | ⬜ Not Started | 0 / 1-2 | 0% | ✅ Yes |
| **10.4 Content Creation** | ⬜ Not Started | 0 / 1 | 0% | ✅ Yes |
| **10.5 Full App Testing** | ⬜ Not Started | 0 / 1-2 | 0% | ✅ Yes |
| **POST-MVP TOTAL** | | **11-17** | | |

**FULL APP TOTAL: 36-51 sessions (MVP 22-33 + Post-MVP 11-17)**

**Legend**: ⬜ Not Started | 🟨 In Progress | ✅ Complete

### Detailed Phase Checklist

#### Phase 1: Foundation & Architecture (3-4 sessions)
- [x] 1.0 Pre-Xcode scaffolding (ios/ structure + API/SSE docs)
- [x] 1.0a Swift DTO + service scaffolding (API client, SSE parser, realtime stubs)
- [x] 1.0b iOS planning docs (architecture + Phase 1 checklist)
- [x] 1.0c Typed API wrappers + realtime adapter outline
- [x] 1.0d SSE URLSession client + view model shells
- [x] 1.0e API contract test checklist
- [x] 1.0f SwiftUI view shells + auth/session stubs + DI container
- [x] 1.0g Auth adapter + navigation state + realtime mappers
- [x] 1.0h Error mapping + cache strategy + theme stub
- [x] 1.0i Permissions + realtime handling + telemetry notes
- [x] 1.0j Native navigation matrix + cache TTL notes + realtime mapping notes
- [ ] 1.1 Xcode Project Setup
- [ ] 1.2 Core Data Models
- [ ] 1.3 Supabase Integration
- [ ] 1.4 API Service Layer
- [ ] 1.5 Cache Layer
- [ ] 1.6 Theme System

#### Phase 2: Navigation & Layout (3-4 sessions)
- [ ] 2.1 Main App Structure
- [ ] 2.2 Sidebar + Section List
- [ ] 2.3 Resizable Sidebar (macOS/iPadOS)
- [ ] 2.4 Detail Views (native layouts)
- [ ] 2.5 Toolbar + Commands (platform-specific)
- [ ] 2.6 Settings Sheet

**Native UX Requirements (Phase 2)**
- Use `NavigationSplitView` for macOS/iPad, `NavigationStack` or tabbed layout for iPhone.
- Use native toolbars and `ToolbarItem` placements instead of a web-style header bar.
- Embrace native behaviors: context menus, keyboard shortcuts, search fields, inspector panels.

**Platform UX Matrix (Phase 2)**
- **macOS**: Sidebar + content + optional inspector; toolbar with primary actions; multiple windows.
- **iPadOS**: 2-3 column split view; contextual toolbars; drag and drop between panes.
- **iOS**: Tab bar for top-level sections; stack navigation for detail; bottom sheets for actions.

#### Phase 3: Chat Viewer (4-5 sessions MVP, 5-7 full)
**MVP Scope: Read-Only Chat Viewer**
- [ ] 3.1 Conversation List
- [ ] 3.2 Chat Window Layout
- [ ] 3.3 SSE Streaming Implementation (for cross-device updates)
- [ ] 3.4 Message List
- [ ] 3.5 Message Rendering (MarkdownUI)
- [ ] 3.6 Tool Call Visualization
- [ ] 3.6a SSE UI Event Handling (note/website/theme/scratchpad/prompt/tool_start/tool_end)
- [ ] 3.8 Real-time Conversation Sync

**Native UX Requirements (Phase 3)**
- Use native list/stack layouts with Dynamic Type and VoiceOver labels.
- Prefer native context menus and swipe actions for message utilities.
- macOS: command-click selection, keyboard navigation, and copy/select behaviors.

**Post-MVP (Phase 10.1): Chat Input**
- [ ] 3.7 Chat Input (text editor, send button, attachments)

#### Phase 4: Note Viewer (2-3 sessions MVP, 7-10 full)
**MVP Scope: Read-Only Note Viewer**
- [ ] 4.1 File Tree Browser (expand/collapse, search, navigation)
- [ ] 4.2 Read-Only Note Viewer (MarkdownUI rendering)
- [ ] 4.2a Scratchpad Note Mapping (special title + realtime updates)
- [ ] 4.6 Search Notes
- [ ] 4.7 Real-time Sync (see updates from other devices)

**Native UX Requirements (Phase 4)**
- Use native outline/list patterns for the tree (`OutlineGroup` on macOS/iPad).
- Use native text selection, share sheet, and Quick Look for attachments.

**Post-MVP (Phases 10.2-10.3): Editing Capabilities**
- [ ] 4.2 Native Markdown Editor (RichTextKit or custom)
- [ ] 4.3 Editor Toolbar (15+ formatting options)
- [ ] 4.4 Save/Dirty State (auto-save, dirty indicator)
- [ ] 4.5 Note Operations (create, rename, move, delete, pin)

#### Phase 5: File Viewing (4-6 sessions)
**MVP Scope: Full (already read-only)**
- [ ] 5.1 Workspace File Tree View
- [ ] 5.2 Workspace File Operations (rename, move, delete)
- [ ] 5.3 Ingestion File List + Status (jobs, pinned order, processed content)
- [ ] 5.4 File Viewer (Quick Look first, native viewers as needed)
- [ ] 5.5 PDF Viewer (PDFKit)
- [ ] 5.6 Image Viewer (pinch-zoom, pan)
- [ ] 5.7 Audio/Video Player (AVFoundation)
- [ ] 5.8 Spreadsheet Viewer
- [ ] 5.9 Markdown Extraction Display
- [ ] 5.10 File Operations (view only - download, pin/unpin)

**Native UX Requirements (Phase 5)**
- Prefer Quick Look where it improves native affordances and share workflows.
- Use native file pickers, share sheets, and drag-drop on macOS/iPadOS.

**Note**: File upload and ingestion deferred to post-launch (not part of MVP or Phase 10)

#### Phase 6: Website Viewer (1-2 sessions MVP, 2-3 full)
**MVP Scope: Read-Only Website Viewer**
- [ ] 6.1 Website List (grouped by domain, search, pinned)
- [ ] 6.2 Website Viewer (WKWebView or MarkdownUI)
- [ ] 6.4 Website Operations (view only - pin/unpin, open in Safari)
- [ ] 6.5 Real-time Sync

**Native UX Requirements (Phase 6)**
- Use `SFSafariViewController` on iOS for external viewing.
- Use `WKWebView` in-app only when needed; prefer markdown/native text for speed and accessibility.

**Post-MVP (Phase 10.4): Content Creation**
- [ ] 6.3 Save Website (URL input, validation, loading state)

#### Phase 7: Additional Features (2-3 sessions MVP, 3-4 full)
**MVP Scope: View-Only**
- [ ] 7.1 Memory Management (view memories, search)
- [ ] 7.3 Settings Panel (view profile, settings - read-only)
- [ ] 7.3a Skills Management (view skills, enable/disable)
- [ ] 7.3b Things Integration (native macOS/iOS; bridge is web-only legacy)
- [ ] 7.4 Weather Integration
- [ ] 7.5 Keyboard Shortcuts (macOS)

**Native UX Requirements (Phase 7)**
- Use native Settings layouts (Form + sections) and platform conventions.
- macOS: use menu bar commands and keyboard shortcuts for key actions.

**Post-MVP (Future Transition)**
- [ ] 7.T1 Task System Migration (replace Things dependency with in-app todo management)
  - Sessions: 3-5 (estimate)

**Post-MVP (Phase 10.4): Editing**
- [ ] 7.1 Memory Management (add, edit, delete memories)
- [ ] 7.2 Scratchpad (editable with auto-save)

#### Phase 8: Platform Optimization (5-7 sessions)
**MVP Scope: Full**
- [ ] 8.1 iPhone-Specific Layout (read-only optimized)
- [ ] 8.2 iPad-Specific Layout
- [ ] 8.3 macOS-Specific Features
- [ ] 8.4 Animations & Transitions
- [ ] 8.5 Performance Optimization
- [ ] 8.6 Accessibility (VoiceOver, Dynamic Type)
- [ ] 8.7 Error Handling
- [ ] 8.8 Loading States
- [ ] 8.9 Offline Behavior (cached reading)

#### Phase 9: MVP Testing & Refinement (3-4 sessions MVP, 4-6 full)
**MVP Scope: Read-Only Testing**
- [ ] 9.1 Integration Testing (all view features)
- [ ] 9.2 Real-World Usage (daily use as reference app)
- [ ] 9.3 Bug Fixes
- [ ] 9.4 Edge Cases (very long content, slow network, empty states)
- [ ] 9.5 Polish

**Post-MVP (Phase 10.5): Full App Testing**
- [ ] Test editing features
- [ ] Test creation workflows
- [ ] End-to-end capability parity validation (native UX)

---

### Phase 10: Editing Capabilities (POST-MVP)
**Sessions: 11-17 | Added after MVP delivery**

#### Phase 10.1: Chat Input (2-3 sessions)
- [ ] Text input with auto-expanding height
- [ ] Send button (disabled when empty)
- [ ] SSE streaming for sending messages
- [ ] File attachment picker (optional)
- [ ] Keyboard shortcuts (Cmd+Enter on Mac)

#### Phase 10.2: Markdown Editor (6-9 sessions) - MOST COMPLEX
- [ ] **Critical Decision**: RichTextKit vs Custom UITextView/NSTextView
- [ ] Basic markdown editing with RichTextKit integration
- [ ] Editor toolbar (bold, italic, headings, lists, etc.)
- [ ] Advanced formatting (tables, links, code blocks)
- [ ] Syntax highlighting for code blocks
- [ ] Live preview option (optional)
- [ ] Performance optimization for long documents

**Decision Gate (After Session 3-5 of 10.2):**
Evaluate RichTextKit capabilities. Choose:
- Option A: Continue with RichTextKit + workarounds
- Option B: Build custom UITextView wrapper (adds 3-5 sessions)
- Option C: Reduce scope (defer tables/advanced features)

#### Phase 10.3: Note Operations (1-2 sessions)
- [ ] Create new note (modal dialog for name/folder)
- [ ] Rename note (alert with text input)
- [ ] Move to folder (picker sheet)
- [ ] Delete note (confirmation alert)
- [ ] Pin/unpin toggle
- [ ] Archive/unarchive
- [ ] Save with dirty state tracking
- [ ] Auto-save with 2-second debounce

#### Phase 10.4: Content Creation (1 session)
- [ ] Save websites (URL input sheet with validation)
- [ ] Add/edit/delete memories
- [ ] Editable scratchpad with auto-save

#### Phase 10.5: Full App Testing (1-2 sessions)
- [ ] Test all editing workflows
- [ ] Test creation and deletion
- [ ] Verify capability parity with native UX
- [ ] Final polish and bug fixes

### Critical Milestones

#### MVP Milestones (Read-Only App)

- [ ] **Milestone 1**: Authentication & API calls working (End of Phase 1)
- [ ] **Milestone 2**: Can view conversations with real-time updates (End of Phase 3)
- [ ] **Milestone 3**: Can read notes in file tree (End of Phase 4)
- [ ] **Milestone 4**: Can view all file types (End of Phase 5)
- [ ] **Milestone 5**: All view features implemented (End of Phase 7)
- [ ] **Milestone 6**: App feels polished on all platforms (End of Phase 8)
- [ ] **MVP COMPLETE**: Read-only app ready for daily reference use (End of Phase 9)

**MVP Decision Gate**: Evaluate whether to:
1. Ship MVP and take break before Phase 10
2. Continue immediately to editing capabilities
3. Iterate on MVP based on real-world usage

#### Post-MVP Milestones (Full App)

- [ ] **Milestone 7**: Can send chat messages (End of Phase 10.1)
- [ ] **Milestone 8**: Can create and edit notes (End of Phase 10.2-10.3)
- [ ] **Milestone 9**: Can create content everywhere (End of Phase 10.4)
- [ ] **FULL APP COMPLETE**: Capability parity with native UX (End of Phase 10.5)

### Session Log

| Date | Phase | Sessions | Hours | Notes |
|------|-------|----------|-------|-------|
| - | - | 0 | 0.0 | Awaiting start |

---

## MVP-First Delivery Strategy

### Why Read-Only MVP First?

This plan takes a **two-phase delivery approach**: ship a read-only viewer app first (MVP), then add editing capabilities (Post-MVP). This strategy provides significant benefits for solo development with context switching.

### Benefits of MVP-First Approach

**1. Faster Time to Value (7-11 weeks vs 12-18 weeks)**
- Get a functional, useful app in ~40% less time
- Can use app daily for reference/viewing while editing remains in the desktop workflow
- Natural break point for context switching to other features

**2. De-Risks Hardest Technical Challenges**
- Validates architecture before investing in markdown editor (7-10 sessions)
- Proves SSE streaming, real-time sync, and multi-platform layouts work
- Markdown editor is explicitly called out as "highest complexity" in original plan
- Can make informed decision on RichTextKit vs custom solution after MVP

**3. Natural Architecture Validation**
- MVVM architecture proven in production use
- Service layer design validated
- Cache strategy performance tested
- Navigation patterns refined through real-world usage

**4. Perfect for Context Switching**
```
Weeks 1-7:   Build read-only iOS app (MVP)
Weeks 8-10:  Ship MVP, switch to backend features
Weeks 11-15: Return to iOS, add editing (Phase 10)
```

**5. Immediate Daily Use Value**
Even read-only, the app provides genuine utility:
- ✅ Reference notes away from desk
- ✅ Read conversations on iPad/iPhone
- ✅ View PDFs and files on the go
- ✅ Check memories quickly
- ✅ Browse archived websites
- ✅ Real-time sync (see updates from other devices instantly)

### What's Included in MVP

**✅ Full Viewing Capabilities:**
- View all conversations with real-time updates
- Browse and read all notes (file tree, search, syntax highlighting)
- View all file types (PDF, images, videos, audio, spreadsheets)
- Browse archived websites
- View memories
- Native navigation per platform (NavigationSplitView/NavigationStack/tabbed)
- Multi-platform optimization (iPhone, iPad, macOS)
- Real-time sync across devices
- Offline cached reading

**✅ Technical Foundations:**
- Complete authentication (Supabase)
- API service layer
- Cache management
- Theme system
- SSE streaming (for watching updates)
- Real-time subscriptions

### What's Deferred to Post-MVP

**❌ Editing Features (Phase 10):**
- Chat input and sending messages
- Markdown editor with toolbar
- Note creation/editing/deletion
- Website saving
- Memory editing
- Scratchpad editing

---

## Native API and Sync Strategy

**Native-first data sources**
- Use platform frameworks for viewing and interaction (Quick Look, PDFKit, AVFoundation, CoreLocation).
- SwiftUI should use native Things APIs (no bridge dependency).

**Backend as sync + AI layer**
- Backend APIs power AI features and cross-device sync.
- UI flows should follow Apple HIG even if existing UX differs.

**Local-first caching**
- Cache primary lists and recent items for fast startup and offline reading.
- Revalidate in background and reconcile realtime updates.

**Why Defer These:**
- Markdown editor alone: 6-9 sessions (most complex component)
- Chat input: 2-3 sessions
- Combined: ~40% of total development time
- Can be added as cohesive Phase 10 after architecture is validated

### MVP Decision Gate

At the end of Phase 9 (MVP Testing), evaluate:

**Option 1: Ship MVP & Take Break** (Recommended)
- Use read-only app daily for 2-4 weeks
- Identify UX improvements through real usage
- Switch to backend development
- Return to Phase 10 when ready for editing features

**Option 2: Continue to Phase 10 Immediately**
- Momentum is high, keep building
- Complete full app in one continuous push
- Good if iOS momentum is strong and motivation high

**Option 3: Iterate on MVP**
- Real-world usage reveals UX issues
- Fix performance bottlenecks
- Polish before adding editing complexity

### MVP Delivery Contents

**What You Can Do With MVP:**
```
✅ Open app on iPhone/iPad/Mac
✅ Log in with Supabase auth
✅ View all conversations
✅ Read all messages with markdown rendering
✅ See tool calls and streaming updates from other devices
✅ Browse note file tree
✅ Read notes with syntax highlighting
✅ Search across all notes
✅ View PDFs with zoom/scroll
✅ Play videos and audio
✅ Browse spreadsheet data
✅ Read archived websites
✅ Check your memories
✅ See real-time updates from other devices
✅ Use offline (cached content)
```

**What You Can't Do (Yet):**
```
❌ Send chat messages
❌ Create/edit notes
❌ Save new websites
❌ Add/edit memories
❌ Edit scratchpad
```

### Post-MVP Phase 10 Breakdown

When ready to resume (estimated 11-17 additional sessions):

| Component | Sessions | Complexity | Notes |
|-----------|----------|------------|-------|
| Chat Input | 2-3 | Medium | Text editor, send button, SSE for sending |
| Markdown Editor | 6-9 | **Very High** | RichTextKit or custom solution, critical decision point |
| Note Operations | 1-2 | Low | Create, rename, move, delete with API calls |
| Content Creation | 1 | Low | Save websites, edit memories, scratchpad |
| Full Testing | 1-2 | Medium | End-to-end capability parity validation (native UX) |

**Critical Decision in Phase 10.2:**
After 3-5 sessions evaluating RichTextKit for markdown editing:
- Continue with RichTextKit + workarounds
- Build custom UITextView/NSTextView wrapper (+3-5 sessions)
- Reduce scope (defer tables/advanced formatting)

### Why This Works for Your Project

**Solo Development Reality:**
- You'll want breaks from iOS during 12-18 week timeline
- Backend features and improvements will come up
- MVP provides a natural stopping point that's still valuable
- Editing features can wait until you're ready to focus again

**Risk Mitigation:**
- Markdown editor is largest unknown (originally flagged as "highest complexity")
- Validate everything else works before investing 6-9 sessions in editor
- If editing proves too complex, MVP is still a useful app

**User Value:**
- A read-only reference app has genuine daily utility
- You can use it immediately while editing remains in the desktop workflow
- Real-world usage informs editing UX decisions

---

## Repository Structure & Development Workflow

### Monorepo Approach (Recommended)

The iOS app will be developed within the existing repository as a monorepo, rather than as a separate repository or long-lived branch. This approach provides several critical benefits:

**Benefits:**
- Backend API changes are immediately visible to iOS development
- Shared database migrations affect both frontends simultaneously
- Single source of truth for API contracts and documentation
- Easy context switching between backend and iOS work
- Git history shows complete evolution across all platforms
- No complicated merge conflicts from long-running branches

**Repository Structure:**
```
sideBar/
├── backend/          # Existing FastAPI backend
│   ├── api/
│   ├── alembic/
│   └── ...
├── frontend/         # Existing SvelteKit web app
│   ├── src/
│   └── ...
├── ios/              # New SwiftUI universal app
│   ├── sideBar.xcodeproj
│   ├── sideBar/
│   │   ├── Views/
│   │   ├── ViewModels/
│   │   ├── Services/
│   │   ├── Models/
│   │   └── Utilities/
│   └── ...
└── docs/             # Shared documentation and plans
    └── plans/
```

### Development Workflow

**Recommended: Direct commits to `main`**

Since the iOS app lives in its own `ios/` directory and doesn't conflict with existing code, you can work directly on `main`:

```bash
# Work on iOS feature
git checkout main
cd ios/
# make iOS changes
git add ios/
git commit -m "feat(ios): implement chat streaming"

# Switch to backend work
cd ../backend/
# make backend changes
git add backend/
git commit -m "feat(api): add new endpoint for iOS"

# iOS automatically sees backend changes
```

**Alternative: `ios-app` branch with periodic syncs**

If you prefer more isolation during initial development:

```bash
# iOS development
git checkout -b ios-app
# work on iOS features
git commit -m "feat(ios): implement foundation"

# Periodically sync backend changes
git checkout ios-app
git merge main  # Pull in backend/API changes

# When iOS feature is stable
git checkout main
git merge ios-app
```

### Git Ignore Updates

Add iOS-specific entries to `.gitignore`:

```gitignore
# Xcode
ios/**/*.xcodeproj/*
!ios/**/*.xcodeproj/project.pbxproj
!ios/**/*.xcodeproj/xcshareddata/
ios/**/*.xcworkspace/*
!ios/**/*.xcworkspace/contents.xcworkspacedata
ios/**/xcuserdata/
ios/**/*.xcscmblueprint
ios/**/*.xccheckout

# Swift Package Manager
ios/**/.build/
ios/**/Packages/
ios/**/*.swiftpm

# CocoaPods (if used)
ios/**/Pods/
ios/**/*.podspec

# Build artifacts
ios/**/DerivedData/
ios/**/build/

# macOS
.DS_Store
```

### Continuous Integration

Update CI/CD to handle both frontends:

```yaml
# .github/workflows/ios.yml
name: iOS Build
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build iOS
        run: |
          cd ios
          xcodebuild -project sideBar.xcodeproj -scheme sideBar build
```

### Key Advantages for This Project

1. **API contract visibility**: If you modify `/api/chat` endpoint, you'll immediately know to update iOS
2. **Migration sync**: Database migrations in `backend/alembic/` are visible when building iOS features
3. **Documentation coherence**: API docs, plans, and implementation stay together
4. **No merge debt**: Unlike long-lived branches, you don't accumulate painful merge conflicts
5. **Natural breaks**: Commit iOS work, switch to backend for a session, return to iOS later

---

## Phase 1: Foundation & Architecture
**Sessions: 3-4 | Critical Path: Yes**

### Objectives
- Establish solid architectural foundation
- Set up universal app target
- Implement authentication
- Create core service layer

### Key Deliverables

**1.1 Xcode Project Setup**
- Create new SwiftUI app with universal target (macOS 26, iOS 26, iPadOS 26)
- Configure build settings for each platform
- Set up folder structure mirroring current organization:
  ```
  Views/
    Chat/
    Notes/
    Files/
    Websites/
    Shared/
  ViewModels/
  Services/
  Models/
  Utilities/
  ```

**1.2 Core Data Models** (Swift structs mirroring TypeScript types)
- `User` (profile, auth state)
- `Conversation` (id, title, created_at, etc.)
- `Message` (role, content, tool_calls, streaming state)
- `Note` (id, title, content, path, pinned, archived)
- `IngestionFile` (id, name, type, status, markdown_path)
- `Website` (id, url, title, content, domain, pinned)
- `Memory` (id, content, path)
- `ToolCall` (id, name, arguments, status, result)

**1.3 Supabase Integration**
- Add Supabase Swift SDK via SPM
- Create `AuthService` class:
  - Email/password login
  - Session management with Keychain
  - Auto-refresh token handling
  - Logout
- Test authentication flow

**1.4 API Service Layer**
- Create `APIClient` base class:
  - URLSession configuration
  - Bearer token injection from Keychain
  - Error handling (decode HTTP errors to user messages)
  - Request/response logging
- Implement API service classes:
  - `ConversationsAPI`
  - `NotesAPI`
  - `IngestionAPI`
  - `WebsitesAPI`
  - `MemoriesAPI`
  - `SettingsAPI`

**1.5 Cache Layer**
- Create `CacheManager` using UserDefaults + FileManager:
  - TTL-based caching (mirroring existing cache strategy)
  - Cache keys versioning
  - Background revalidation
- Implement cache for:
  - Conversation list (5 min TTL)
  - Notes tree (10 min TTL)
  - File tree (10 min TTL)

**1.6 Theme System**
- Extract CSS custom properties to Swift:
  ```swift
  struct AppTheme {
    static let primary = Color(/* OKLCH color */)
    static let foreground = Color(/* ... */)
    // ... all theme colors
  }
  ```
- Create `@AppStorage` wrapper for dark mode preference
- Implement theme switching

### Technical Decisions
- **Architecture**: MVVM with Combine (or @Observable on iOS 17+)
- **Dependency Injection**: Protocol-based for testability
- **Navigation**: NavigationStack (iOS) + NavigationSplitView (iPad/Mac)

### Risks & Challenges
- Supabase Swift SDK may have different auth patterns than JS
- Need to ensure secure Keychain storage for tokens

---

## Phase 2: Core Navigation & Layout
**Sessions: 3-4 | Critical Path: Yes**

### Objectives
- Build main app shell
- Implement sidebar navigation
- Create resizable split view layout (macOS/iPadOS)
- Set up native toolbar commands

### Key Deliverables

**2.1 Main App Structure**
- Create `ContentView` as root:
  - Login screen vs. authenticated view switching
  - NavigationSplitView for iPad/Mac
  - NavigationStack for iPhone
- Implement state routing between sections

**2.2 Sidebar Rail** (Icon Navigation)
- Replicate `SidebarRail.svelte` in SwiftUI:
  ```swift
  enum SidebarSection {
    case notes, websites, workspace, history
  }
  ```
- 56px width vertical rail with:
  - Menu toggle button (top)
  - Section icons (Notes, Websites, Files, Chat)
  - Profile avatar (bottom)
- Active state styling
- Hover effects (macOS only)

**2.3 Resizable Sidebar Panels**
- **macOS**: Use `NSSplitViewController` wrapped in SwiftUI
  - Min/max constraints (200px - 500px)
  - Snap points at 33%, 40%, 50%
  - Persist width to UserDefaults
- **iOS/iPad**: Custom drag gesture on divider
  - Same constraints and snap logic
  - Disable on iPhone (full-screen views instead)

**2.4 Panel Content Views**
- Create placeholder views for:
  - `ConversationsPanel` (will expand in Phase 3)
  - `NotesPanel` (Phase 4)
  - `FilesPanel` (Phase 5)
  - `WebsitesPanel` (Phase 6)
- Implement section switching logic

**2.5 Site Header Bar**
- Replicate header layout:
  - Logo + brand text (left)
  - Date/time/location/weather (center-right)
  - Layout swap button (hide on mobile)
  - Scratchpad popover
  - Theme toggle
- Integrate weather API (replicate current endpoint)
- Live clock updates (Timer.publish)

**2.6 Settings Sheet**
- Modal sheet presentation
- Tab-based settings (Profile, Memories, Shortcuts, API)
- Profile image picker (UIImagePickerController wrapper)

### Technical Decisions
- Use `@StateObject` for ViewModels to persist across view updates
- Sidebar width: `@AppStorage("sidebarWidth")` for persistence
- Active section: `@State` in root view, passed down

### Risks & Challenges
- NSSplitView integration with SwiftUI can be finicky (may need NSViewRepresentable)
- iPhone navigation needs different pattern (full-screen modal sheets)

---

## Phase 3: Chat Interface (Highest Priority)
**Sessions: 5-7 | Critical Path: Yes**

### Objectives
- Build fully functional chat with streaming
- Implement SSE message streaming
- Create message rendering with markdown
- Tool call visualization

### Key Deliverables

**3.1 Conversation List**
- Replicate `ConversationList.svelte`:
  - List of conversations with timestamps
  - Search bar with debounce
  - New conversation button
  - Delete conversation (swipe action on iOS, context menu on Mac)
  - Real-time updates via Supabase
- Pull-to-refresh on iOS
- Keyboard navigation on Mac

**3.2 Chat Window Layout**
- Main chat container:
  - Message list (scrollable)
  - Input bar (sticky bottom)
  - Tool call status area
- Auto-scroll to bottom on new messages
- Scroll position persistence

**3.3 SSE Streaming Implementation**
This is complex - here's the approach:

```swift
class SSEClient {
  func streamChat(conversationId: UUID, message: String) async throws -> AsyncThrowingStream<SSEEvent, Error> {
    var request = URLRequest(url: chatURL)
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

    let (bytes, response) = try await URLSession.shared.bytes(for: request)

    return AsyncThrowingStream { continuation in
      Task {
        var buffer = ""
        for try await byte in bytes {
          buffer.append(Character(UnicodeScalar(byte)))
          if buffer.hasSuffix("\n\n") {
            // Parse SSE event from buffer
            let event = parseSSE(buffer)
            continuation.yield(event)
            buffer = ""
          }
        }
        continuation.finish()
      }
    }
  }
}
```

- Parse SSE events (`data:`, `event:`, `id:`)
- Handle event types: `token`, `tool_call_start`, `tool_call_end`, `error`, `done`
- Reconnection logic on connection drop

**3.4 Message List**
- `LazyVStack` for performance
- Message bubbles with:
  - User messages (right-aligned, colored background)
  - Assistant messages (left-aligned, markdown rendering)
  - Timestamps
  - Tool calls (inline)
- Scroll to bottom button (when not at bottom)
- Loading indicator during streaming

**3.5 Message Rendering**
Use **MarkdownUI** library (open-source, well-maintained):
```swift
import MarkdownUI

Markdown(message.content)
  .markdownTheme(.gitHub) // or custom theme
  .markdownCodeSyntaxHighlighter(.splash(theme: .sunset))
```

This handles:
- Headings
- Lists
- Code blocks with syntax highlighting
- Links
- Tables
- Images

**3.6 Tool Call Visualization**
- Replicate `ToolCall.svelte`:
  - Tool name badge
  - Arguments (collapsed JSON)
  - Status: running (spinner) → success (checkmark) / error (X)
  - Result display (expandable)
- Animate transitions

**3.7 Chat Input**
- `TextEditor` with:
  - Auto-expanding height (max 6 lines)
  - Placeholder text
  - Send button (disabled when empty)
  - Attachment button
- File attachment picker:
  - Show thumbnails of attached files
  - Remove attachment button
- Keyboard shortcuts (Cmd+Enter to send on Mac)

**3.8 Real-time Conversation Sync**
```swift
class ConversationsViewModel: ObservableObject {
  @Published var conversations: [Conversation] = []
  private var channel: RealtimeChannel?

  func setupRealtime() {
    channel = supabase.channel("conversations")
      .on(.insert) { [weak self] in
        self?.handleNewConversation($0)
      }
      .on(.update) { [weak self] in
        self?.handleUpdatedConversation($0)
      }
      .on(.delete) { [weak self] in
        self?.handleDeletedConversation($0)
      }
      .subscribe()
  }
}
```

### Technical Decisions
- **SSE**: Use AsyncSequence with manual parsing (no built-in SSE in URLSession)
- **Markdown**: MarkdownUI library (maintained, extensible)
- **Real-time**: Supabase Realtime channels per resource type

### Risks & Challenges
- **SSE streaming** is the biggest technical risk - test thoroughly with slow connections
- **Markdown rendering performance** with very long messages (may need pagination)
- **Tool call updates** during streaming need careful state management

---

## Phase 4: Note Editor (Highest Complexity)
**Sessions: 6-8 | Critical Path: Yes**

### Objectives
- Build native markdown editor with formatting toolbar
- Implement file tree browser
- Add pin/archive/search functionality
- Real-time sync

### Key Deliverables

**4.1 File Tree Browser**
- Replicate `FileTree.svelte` with `OutlineGroup`:
  ```swift
  OutlineGroup(noteTree, children: \.children) { node in
    NoteTreeRow(node: node)
      .contextMenu {
        Button("Rename") { ... }
        Button("Move") { ... }
        Button("Delete") { ... }
      }
  }
  ```
- Expand/collapse folders
- Pinned section at top
- Drag-drop to reorder (may defer to later phase)
- Search filter
- Context menus

**4.2 Native Markdown Editor**
This is the most complex component. Approach:

**Option A**: Use `TextEditor` + **RichTextKit** library
- Open-source, maintained library
- Provides toolbar, formatting commands
- Markdown syntax support
- Customizable

**Option B**: Use `TextEditor` + **MarkdownEditor** library
- Specifically designed for markdown
- Live preview option
- Syntax highlighting

**Option C**: Build custom using `UITextView`/`NSTextView` wrapper
- Full control
- Most work
- Best performance potential

**Recommendation**: Start with RichTextKit (Option A), fall back to custom if needed.

**4.3 Editor Toolbar**
Replicate TipTap toolbar:
- Bold, Italic, Strikethrough
- Headings (H1-H6)
- Bullet list, Ordered list, Checklist
- Blockquote
- Code block
- Table insertion
- Link insertion
- Horizontal rule

On iOS: Use toolbar above keyboard
On Mac: Top toolbar in editor area

**4.4 Save/Dirty State**
```swift
class NoteEditorViewModel: ObservableObject {
  @Published var content: String = ""
  @Published var isDirty: Bool = false
  private var saveWorkItem: DispatchWorkItem?

  func contentDidChange() {
    isDirty = true

    // Debounce save (2 seconds)
    saveWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      await self.save()
    }
    saveWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
  }
}
```

- Visual dirty indicator (* in title)
- Auto-save with 2-second debounce
- Confirm navigation if unsaved changes

**4.5 Note Operations**
- Create new note (modal dialog for name/folder)
- Rename (alert with text input)
- Move to folder (picker sheet)
- Pin/unpin (toggle)
- Archive/unarchive
- Delete (confirmation alert)

**4.6 Search Notes**
- Debounced search input
- Filter tree by title/content
- Highlight matches
- Search across all notes (global search)

**4.7 Real-time Sync**
```swift
channel = supabase.channel("notes")
  .on(.insert) { [weak self] payload in
    let newNote = decode(payload)
    self?.notes.append(newNote)
    self?.refreshTree()
  }
  .on(.update) { [weak self] payload in
    let updatedNote = decode(payload)
    self?.mergeNote(updatedNote) // Handle conflict if currently editing
  }
  .subscribe()
```

- Handle external edits while user is editing (show banner: "This note was updated externally. Reload?")
- Refresh tree on folder changes

### Recommended Session Breakdown (Phase 4)
Given the complexity of this phase, here's a suggested breakdown:

- **Sessions 1-2**: File tree browser implementation with expand/collapse, search, and context menus
- **Sessions 3-5**: RichTextKit integration, basic markdown editing, and toolbar setup
- **Session 6-7**: Advanced formatting features (tables, links, code blocks) and customization
- **Session 8-9**: Save/dirty state, auto-save debouncing, and note operations (create, rename, move, delete)
- **Session 10**: Real-time sync, conflict handling, and integration testing

**Critical Decision Point (After Session 5)**:
Evaluate RichTextKit capabilities. If major feature gaps exist (especially for tables or complex formatting):
- **Option A**: Continue with RichTextKit + workarounds for missing features
- **Option B**: Switch to custom UITextView/NSTextView solution (adds 3-5 sessions)
- **Option C**: Reduce scope (defer tables, advanced formatting to post-launch)

### Technical Decisions
- **Editor library**: RichTextKit (extensible, maintained)
- **Conflict resolution**: Last-write-wins with user notification
- **Tree state**: Persist expanded folders to UserDefaults

### Risks & Challenges
- **Native markdown editing** is significantly more work than a web editor
- **Tables in markdown** are complex to edit natively
- **Conflict resolution** during simultaneous edits across devices
- **Performance** with large notes (>10,000 words)

---

## Phase 5: File Viewing (Upload & Ingestion Deferred)
**Sessions: 4-6 | Critical Path: No**

### Objectives
- Build file tree browser for existing workspace files
- Implement native file viewing (Quick Look first, native viewers as needed)
- **Note**: File uploads and ingestion processing are intentionally deferred to Phase 10 (post-MVP)

### Key Deliverables

**5.1 File Tree View**
- Similar to notes tree, but for workspace files
- Show file type icons (SF Symbols)
- File size indicators
- Pinned files section
- Context menus (Download, Rename, Delete)

**5.2 File Upload** (Deferred)
```swift
class FileUploadManager: ObservableObject {
  @Published var uploadProgress: [UUID: Double] = [:]

  func uploadFile(_ url: URL) async throws -> IngestionFile {
    let uploadTask = URLSession.shared.uploadTask(with: request, fromFile: url)

    // Observe progress
    for await progress in uploadTask.progress.publisher(for: \.fractionCompleted).values {
      await MainActor.run {
        uploadProgress[fileId] = progress
      }
    }

    let (data, response) = try await uploadTask.result
    return decodeResponse(data)
  }
}
```

- File picker (UIDocumentPickerViewController / NSOpenPanel)
- Multiple file upload support
- Progress bars in UI
- Cancel upload
- Retry on failure

**5.3 Ingestion Status Polling** (Deferred)
After upload, poll backend for processing status:
```swift
func pollIngestionStatus(fileId: UUID) async throws {
  while true {
    let status = try await ingestionAPI.getStatus(fileId)

    switch status.state {
    case .completed:
      // Update UI, stop polling
      return
    case .failed:
      // Show error
      throw IngestionError.failed(status.error)
    case .processing:
      // Continue polling
      try await Task.sleep(nanoseconds: 2_000_000_000) // 2 sec
    }
  }
}
```

**5.4 Universal File Viewer**
Create `UniversalViewer` that routes to specific viewers:

```swift
struct UniversalViewer: View {
  let file: IngestionFile

  var body: some View {
    switch file.type {
    case .pdf:
      PDFViewer(url: file.url)
    case .image:
      ImageViewer(url: file.url)
    case .audio:
      AudioPlayer(url: file.url)
    case .video:
      VideoPlayer(player: AVPlayer(url: file.url))
    case .spreadsheet:
      SpreadsheetViewer(data: file.jsonData)
    case .markdown, .text:
      MarkdownViewer(content: file.content)
    }
  }
}
```

**5.5 PDF Viewer (PDFKit)**
```swift
import PDFKit

struct PDFViewer: NSViewRepresentable { // or UIViewRepresentable on iOS
  let url: URL

  func makeNSView(context: Context) -> PDFView {
    let pdfView = PDFView()
    pdfView.document = PDFDocument(url: url)
    pdfView.autoScales = true
    pdfView.displayMode = .singlePageContinuous
    return pdfView
  }
}
```

Features:
- Page navigation (thumbnails sidebar on Mac/iPad)
- Zoom controls
- Search within PDF
- Annotations (if desired)

**5.6 Image Viewer**
- Pinch-to-zoom (iOS)
- Scroll wheel zoom (Mac)
- Pan gesture
- Fit to width/height/original size controls

**5.7 Audio/Video Player**
Use AVFoundation:
```swift
import AVKit

VideoPlayer(player: AVPlayer(url: url))
  .frame(height: 400)
```

For audio, create custom controls with play/pause, scrubber, time labels.

**5.8 Spreadsheet Viewer**
- Display JSON data as table
- Use native `Table` view (macOS) or `List` with columns (iOS)
- Sortable columns
- Search/filter rows

**5.9 Markdown Extraction Display**
- Show extracted markdown in read-only MarkdownUI view
- Download button
- Copy to clipboard

**5.10 File Operations**
- Pin/unpin (updates backend)
- Rename (alert dialog)
- Delete (confirmation)
- Download (save to Files app on iOS, Finder on Mac)

### Technical Decisions
- **PDF**: Native PDFKit (excellent performance, familiar UX)
- **Upload**: URLSession with progress observation
- **Polling**: Simple exponential backoff if needed

### Risks & Challenges
- **Large file uploads** on cellular (handled when uploads are reintroduced)
- **PDFKit** has different UI paradigms on Mac vs iOS (may need conditional layouts)
- **Video playback** performance with large files

---

## Phase 6: Website Archival
**Sessions: 2-3 | Critical Path: No**

### Objectives
- Display archived websites
- Save new websites
- Pin/search functionality

### Key Deliverables

**6.1 Website List**
- List grouped by domain
- Show title, domain, timestamp
- Pin section at top
- Search bar
- Pull-to-refresh

**6.2 Website Viewer**
- Render HTML content:
  ```swift
  import WebKit

  struct WebsiteViewer: NSViewRepresentable {
    let htmlContent: String

    func makeNSView(context: Context) -> WKWebView {
      let webView = WKWebView()
      webView.loadHTMLString(htmlContent, baseURL: nil)
      return webView
    }
  }
  ```
- Or use MarkdownUI if backend provides markdown
- Show metadata (URL, saved date)
- Open in Safari button

**6.3 Save Website**
- Input sheet with URL field
- Validation
- Loading state while fetching
- Show in list when complete

**6.4 Website Operations**
- Pin/unpin
- Delete
- Archive/unarchive
- Open original URL

**6.5 Real-time Sync**
Same pattern as notes/conversations.

### Technical Decisions
- **HTML rendering**: WKWebView (supports full HTML/CSS/JS if needed)
- **Content**: Use markdown if available (lighter, faster)

### Risks & Challenges
- **Minimal** - straightforward feature

---

## Phase 7: Additional Features
**Sessions: 3-4 | Critical Path: No**

### Objectives
- Memory management
- Scratchpad
- Settings
- Weather integration

### Key Deliverables

**7.1 Memory Management**
- List view with path hierarchy
- Add memory (sheet with path + content)
- Edit memory (sheet)
- Delete (swipe action)
- Search memories
- Real-time sync

**7.2 Scratchpad**
- Popover (Mac) or sheet (iOS)
- Simple TextEditor
- Auto-save with debounce
- Real-time sync across devices

**7.3 Settings Panel**
- Profile section:
  - Avatar upload
  - Display name
- Memory section (link to memory management)
- Keyboard shortcuts (Mac only):
  - Display list of shortcuts
  - Customization (if desired)
- API section:
  - PAT display/rotation
- Theme toggle
- About section (version info)

**7.4 Weather Integration**
- Replicate weather API calls
- Location autocomplete (use existing places endpoint)
- Display in toolbar area (platform-appropriate)
- Update every 30 minutes

**7.5 Keyboard Shortcuts (macOS)**
```swift
.keyboardShortcut("1", modifiers: .command)
  .onReceive(...) { activateSection(.notes) }
```

- Cmd+1: Notes
- Cmd+2: Websites
- Cmd+3: Files
- Cmd+4: Chat
- Cmd+N: New conversation/note (context-dependent)
- Cmd+W: Close window (system default)

### Technical Decisions
- **Location**: Use CoreLocation for current location if user permits
- **Shortcuts**: SwiftUI `.keyboardShortcut()` modifier

### Risks & Challenges
- **Minimal** - these are small, contained features

---

## Phase 8: Platform Optimization & Polish
**Sessions: 4-6 | Critical Path: No**

### Objectives
- Optimize for each platform
- Add animations
- Improve performance
- Handle edge cases

### Key Deliverables

**8.1 iPhone-Specific Layout (Narrow Scope)**
- Full-screen navigation (no split view)
- Focus on **Chat + Notes editing**
- Limit panes and advanced controls
- Compact chat input
- Gesture-based navigation (swipe to go back)

**8.2 iPad-Specific Layout**
- Utilize full screen real estate
- Three-column layout option (sidebar | list | detail)
- Keyboard navigation
- External keyboard shortcuts
- Drag-drop between apps (if feasible)

**8.3 macOS-Specific**
- Window size constraints (min 1000x600)
- Toolbar customization
- Menu bar items (File, Edit, View, Window, Help)
- Touch Bar support (if applicable)
- Keyboard focus management

**8.4 Animations & Transitions**
- Smooth section switching
- Message appearance animations
- Tool call state transitions
- Loading skeletons
- Pull-to-refresh animations
- Haptic feedback (iOS)

**8.5 Performance Optimization**
- LazyVStack/LazyHStack for large lists
- Image caching for avatars/thumbnails
- Pagination for conversation history (load more)
- Debounce search queries
- Background tasks for cache refresh

**8.6 Accessibility**
- VoiceOver labels for all interactive elements
- Dynamic Type support (respect user font size)
- Color contrast compliance
- Reduce Motion support
- Keyboard navigation (full app usable via keyboard on Mac)

**8.7 Error Handling**
- Network error recovery (retry, offline mode)
- Form validation errors
- File upload errors
- Authentication errors (redirect to login)
- User-friendly error messages

**8.8 Loading States**
- Skeleton screens for list loading
- Progress indicators for long operations
- Pull-to-refresh
- Infinite scroll loading

**8.9 Offline Behavior**
- Cache messages/notes for reading
- Queue uploads for when online
- Show offline indicator
- Prevent edits in offline mode (or queue them)

### Technical Decisions
- **Animations**: Use SwiftUI's built-in `.animation()` and `withAnimation`
- **Performance**: Profile with Instruments, optimize hot paths

### Risks & Challenges
- **Platform fragmentation** - ensuring consistent UX across devices takes iteration
- **Accessibility** - comprehensive VoiceOver support is time-consuming

---

## Phase 9: Testing & Refinement
**Sessions: 3-5 | Critical Path: Yes**

### Objectives
- Integration testing
- Real-world usage
- Bug fixes
- Edge case handling

### Key Deliverables

**9.1 Integration Testing**
- Test all features end-to-end
- Test across all platforms (Mac, iPad, iPhone)
- Test offline scenarios
- Test poor network conditions
- Test authentication edge cases

**9.2 Real-World Usage**
- Use app daily for own workflows
- Identify UX friction points
- Performance issues
- Missing features/gaps

**9.3 Bug Fixes**
- Fix crashes
- Fix data inconsistencies
- Fix UI glitches
- Fix performance issues

**9.4 Edge Cases**
- Very long messages
- Very long notes
- Large file uploads
- Slow network
- Simultaneous edits
- Empty states
- Error states

**9.5 Polish**
- Smooth animations
- Consistent spacing
- Icon alignment
- Color refinements
- Typography tuning

### Technical Decisions
- **Testing**: Manual testing initially, consider XCTest for critical paths later
- **Crash reporting**: Consider Sentry or Firebase Crashlytics for App Store release

### Risks & Challenges
- **Time-consuming** - testing reveals unexpected issues
- **Iteration** - may need to revisit earlier phases

---

## Critical Technical Challenges & Solutions

### 1. Native Markdown Editor (Highest Risk)
**Challenge**: SwiftUI's TextEditor is basic. Building markdown editing with formatting toolbar is complex.

**Mitigation**:
- Start with **RichTextKit** library (proven, open-source)
- If insufficient, evaluate **MarkdownEditor** library
- If both fail, allocate extra sessions for custom UITextView wrapper
- Consider hybrid: simple editing in native, complex editing in WebView

**Fallback**: Temporarily use TextEditor with markdown syntax (no toolbar) to unblock other work, then enhance.

### 2. SSE Streaming (High Risk)
**Challenge**: Swift doesn't have built-in SSE support. Manual parsing is error-prone.

**Mitigation**:
- Use AsyncSequence with URLSession.bytes
- Write robust SSE parser with unit tests
- Test with slow network simulator
- Implement reconnection logic
- Have AI agent review/test thoroughly

**Fallback**: Poll for new messages every 2 seconds (less elegant, but functional).

### 3. Real-time Sync (Medium Risk)
**Challenge**: Supabase Realtime in Swift may behave differently than JS SDK.

**Mitigation**:
- Test Supabase Realtime early (in Phase 1)
- Handle reconnection gracefully
- Cache-first approach (updates are additive, not authoritative)
- Use local optimistic updates

**Fallback**: Poll for updates every 10-30 seconds.

### 4. Resizable Panels (Medium Risk)
**Challenge**: NSSplitView/SwiftUI integration can be finicky.

**Mitigation**:
- Use NSViewRepresentable wrapper for NSViewController
- Test on all platforms early
- Consider third-party libraries if native approach fails

**Fallback**: Fixed-width sidebar with toggle to hide/show.

### 5. File Upload Progress (Low-Medium Risk)
**Challenge**: Observing upload progress with URLSession requires delegates.

**Mitigation**:
- Use modern URLSession async APIs with progress observation
- Test with large files
- Handle background uploads (if user switches apps)

**Fallback**: Upload without progress indicator (spinner only).

---

## Recommended Work Cadence (Revised)

### Week 1-2: Foundation (Phase 1)
- Day 1-2: Project setup, auth, models
- Day 3-4: API service layer
- Day 5-6: Cache layer, theme system
- **Milestone**: Can authenticate and make API calls

### Week 3-4: Navigation & Chat (Phases 2-3)
- Day 1-2: Main navigation, sidebar
- Day 3-4: Split view layout, toolbars
- Day 5-8: Chat interface, SSE streaming, message rendering
- **Milestone**: Can send/receive messages with streaming

### Week 5-6: Note Editor (Phase 4)
- Day 1-2: File tree browser
- Day 3-5: Markdown editor with toolbar
- Day 6-7: Save/dirty state, operations
- **Milestone**: Can create/edit notes

### Week 7-8: File Viewing (Phase 5, uploads deferred)
- Day 1-2: File tree
- Day 3-4: PDF viewer, image viewer
- Day 5-6: Audio/video, spreadsheets
- **Milestone**: Can view file types (uploads deferred)

### Week 9: Website & Additional Features (Phases 6-7)
- Day 1-2: Website archival
- Day 3-4: Memory management, scratchpad
- Day 5: Settings, weather
- **Milestone**: All features implemented

### Week 10-11: Platform Optimization (Phase 8)
- Day 1-2: iPhone narrow-scope layout
- Day 3-4: iPad/Mac optimizations
- Day 5-6: Animations, performance
- Day 7-8: Accessibility, error handling
- **Milestone**: App feels polished on all platforms

### Week 12: Testing & Refinement (Phase 9)
- Day 1-3: Integration testing, bug fixes
- Day 4-5: Real-world usage, polish
- **Milestone**: App ready for daily use

---

## Estimated Session Breakdown (Revised)

| Phase | Sessions | Hours (Range) | Priority |
|-------|----------|---------------|----------|
| 1. Foundation | 3-4 | 6-16 hrs | Critical |
| 2. Navigation | 3-4 | 6-16 hrs | Critical |
| 3. Chat | 5-7 | 10-28 hrs | Critical |
| 4. Note Editor | 7-10 | 14-40 hrs | Critical |
| 5. File Viewing (uploads deferred) | 4-6 | 8-24 hrs | Medium |
| 6. Websites | 2-3 | 4-12 hrs | Medium |
| 7. Additional | 3-4 | 6-16 hrs | Medium |
| 8. Platform | 5-7 | 10-28 hrs | High |
| 9. Testing | 4-6 | 8-24 hrs | Critical |
| 7.T1 Task System Migration (post-MVP) | 3-5 | 6-20 hrs | Medium |
| **Total (Planned)** | **39-56** | **78-224 hrs** | |

**Note**: The planned breakdown above totals 39-56 sessions including the optional post-MVP task system migration. The timeline estimates below include buffer time for unexpected complexity, iteration, and overruns (particularly in Phases 4 and 8), bringing the realistic total to 40-70 sessions (or 43-75 with the migration).

**Assuming 3-4 sessions/week at 3-4 hours each:**
- **Optimistic**: 9-10 weeks (36-40 sessions × 3 hrs = 108-120 hrs)
- **Realistic**: 12-14 weeks (45-55 sessions × 3.5 hrs = 157-192 hrs)
- **Conservative**: 15-18 weeks (51-70 sessions × 4 hrs = 204-280 hrs)
- **With migration**: +1-2 weeks (3-5 sessions)

---

## Dependencies & Blocking Relationships

```
Phase 1 (Foundation) → Phase 2 (Navigation) → Phase 3 (Chat)
                                              ↘ Phase 4 (Notes)
                                              ↘ Phase 5 (Files)
                                              ↘ Phase 6 (Websites)

Phase 3, 4, 5, 6 → Phase 7 (Additional Features)
All Phases → Phase 8 (Platform Optimization)
All Phases → Phase 9 (Testing)
```

**Critical Path**: 1 → 2 → 3 → 4 → 8 → 9

You can parallelize:
- Phase 5, 6, 7 can be worked on in any order after Phase 3
- Phase 8 can start once core features (1-4) are functional

---

## Key Decisions Requiring Input During Development

1. **Markdown Editor Evaluation** (Week 5-6, after Phase 4 Session 5) - **CRITICAL**
   - Evaluate RichTextKit capabilities for tables, advanced formatting
   - If major gaps exist, choose between:
     - **Option A**: Continue with RichTextKit + workarounds (maintains timeline)
     - **Option B**: Build custom UITextView/NSTextView wrapper (adds 3-5 sessions)
     - **Option C**: Reduce scope - defer tables/advanced features to post-launch
   - This decision impacts timeline by up to 1 month if custom solution needed

2. **iPhone Navigation Pattern** (Week 10-11)
   - Tab bar vs. hamburger menu vs. gesture-based navigation
   - Focus on chat + notes simplicity vs. attempting full capability parity

3. **Offline Mode Scope** (Week 11-12)
   - Read-only cached content vs. full offline editing with sync queue
   - Queue-based approach may add 2-3 sessions to Phase 8

4. **Animation Style** (Week 10-11)
   - Subtle/minimal (faster to implement) vs. playful/animated (adds polish)

5. **App Icon & Branding** (Week 11-12)
   - Design app icon for App Store
   - Consider hiring designer vs. AI-generated vs. self-designed

6. **File Upload Timing** (Post-MVP)
   - When to implement deferred Phase 10 (file uploads)
   - Immediately after MVP or wait for user feedback

---

## Recommended Third-Party Libraries

### Essential
- **Supabase Swift SDK**: Authentication, Realtime
- **MarkdownUI**: Markdown rendering (MIT license)

### Strongly Recommended
- **RichTextKit**: Markdown editor with toolbar (MIT license)
- **Kingfisher** or **SDWebImageSwiftUI**: Image loading/caching

### Optional
- **SwiftLint**: Code style enforcement
- **Sentry** or **Firebase Crashlytics**: Crash reporting (for App Store release)

All libraries are actively maintained and have permissive licenses.

---

## Success Metrics

**Definition of Done**:
- [ ] All capabilities available with native UX on Mac, iPad, iPhone
- [ ] Real-time sync working reliably
- [ ] Offline reading supported with smart caching
- [ ] App feels native (not like a web wrapper)
- [ ] Performance is smooth (60fps animations, fast launches)
- [ ] Accessible via VoiceOver
- [ ] Zero critical bugs
- [ ] Ready for daily personal use

---

## Post-Launch Enhancements (Future Phases)

Once core app is complete, consider:

### Phase 10: File Upload & Ingestion (Deferred from Phase 5)
- **File upload** with progress tracking
- **Ingestion job polling** for processing status
- **Upload queue management** with retry logic
- **Background uploads** when app is backgrounded
- **Error handling** for failed uploads
- **Priority**: High - should be implemented after MVP is stable

### Additional Future Enhancements
1. **iOS Widgets**: Quick notes, recent conversations
2. **Share Extension**: Save content to sideBar from Safari/other apps
3. **Shortcuts Integration**: Siri shortcuts for common actions
4. **macOS Menu Bar**: Quick access without opening full app
5. **Universal Clipboard**: Copy on Mac, paste on iPhone
6. **Handoff**: Start conversation on iPhone, continue on Mac
7. **iCloud Sync**: Redundant backend sync for offline-first workflow
8. **Push Notifications**: For real-time updates when app is closed
9. **Collaborative Editing**: Multiple users editing same note
10. **Export/Import**: Backup conversations/notes

---

## Current Frontend Architecture (Reference)

This section is **reference-only** for data flows and feature scope. It is **not** a UI or interaction spec for SwiftUI. Do not mirror these layouts in the native app.

### Technology Stack
- **Framework**: SvelteKit 5 with TypeScript
- **Styling**: Tailwind CSS v4 with CSS custom properties
- **Component Library**: bits-ui (headless components)
- **Icons**: lucide-svelte
- **Build**: Vite
- **Testing**: Vitest

### State Management
Custom Svelte stores:
- `chatStore` - Messages, streaming state, tool calls
- `conversationsStore` - Conversation list with caching
- `editorStore` - Note editing state
- `ingestionStore` - File upload progress tracking
- `websitesStore` - Archived websites
- `memoriesStore` - User memories
- `layoutStore` - UI layout (sidebar width, mode)
- `authStore` - User session (Supabase)
- `treeStore` - File tree for workspace
- `ingestionViewerStore` - Active file viewer state

### Component Architecture
Web-only UI structure for reference. SwiftUI should use native navigation patterns instead.
```
+layout.svelte (App shell)
├── Sidebar (Left nav)
│   ├── SidebarRail (Icon nav)
│   ├── ConversationList
│   ├── NotesPanel (File tree browser)
│   ├── FilesPanel (Workspace files)
│   ├── WebsitesPanel (Archived sites)
│   └── SettingsDialog
└── Main Content
    ├── SiteHeader (Top bar)
    └── Page content (swappable)
        ├── ChatWindow (Main)
        ├── MarkdownEditor (Notes/files)
        ├── UniversalViewer (Files)
        └── WebsitesViewer (Archived sites)
```

### Key Features
1. **Chat Interface**: Real-time streaming via SSE, tool call visualization
2. **Note Editor**: Rich markdown editor (TipTap), folder organization
3. **File Ingestion**: Multi-format (PDF, images, audio, video, spreadsheets)
4. **Website Archival**: Save and view archived websites
5. **Memory System**: Persistent facts for AI context
6. **Real-time Sync**: Supabase Realtime for cross-device updates
7. **Scratchpad**: Quick notes with auto-sync

### Complex Components
Implementation references for behavior and data flow only; do not replicate web UI layout.
- **ChatWindow**: SSE streaming, token appending, tool call updates
- **MarkdownEditor**: TipTap-based editor with 15+ formatting options
- **UniversalViewer**: Multi-format file viewer (40KB+ code)
- **PdfViewer**: Custom PDF rendering with zoom/pan
- **FileTree**: Recursive tree with drag-drop

### API Patterns
- REST endpoints through SvelteKit routes
- SSE for chat streaming
- Supabase Realtime for database changes
- LocalStorage-based cache with TTL
- Background revalidation

---

## Final Thoughts

This is an **ambitious but achievable** project. The existing system is well-architected, which makes migration straightforward conceptually. The main challenges are:

1. **Native markdown editor** - allocate extra time here
2. **SSE streaming** - test thoroughly
3. **Platform-specific UX** - resist the urge to cut corners

With a capable AI agent writing the code and architect/director oversight, a **12-14 week timeline is realistic** for a polished MVP. Allow up to 15-18 weeks if significant complexity arises in the markdown editor or SSE streaming requires substantial rework. The key is to:

- **Start with Phase 1 foundation** - this sets up for success
- **Test incrementally** - don't wait until the end
- **Embrace platform conventions** - don't fight SwiftUI
- **Prioritize core features** - chat and notes are most critical
- **Be ready to adjust scope** - Phase 4 markdown editor may require trade-offs
