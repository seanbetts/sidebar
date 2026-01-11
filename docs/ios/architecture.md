# iOS Architecture Notes

## Goals
- Mirror the web app feature set with native SwiftUI views.
- Keep service layer isolated from views via view models.
- Support realtime updates (Supabase) and chat streaming (SSE).

## Module Layout
- `App/`: app entry point, dependency container, environment config
- `Models/`: Codable DTOs for API payloads
- `Services/`:
  - `Network/`: API client, auth headers, error mapping
  - `Chat/`: SSE streaming client and event dispatch
  - `Realtime/`: Supabase realtime subscription manager
  - `Cache/`: in-memory/disk cache with TTL
- `ViewModels/`: feature view models (Chat, Notes, Files, Websites, Memories, Settings, Tasks)
- `Views/`: SwiftUI screens + shared components
- `Utilities/`: helpers (date parsing, URL helpers, decoding)

## Data Flow
- Views -> ViewModels -> Services -> API
- Services emit updates to ViewModels via async/await or Combine publishers.
- Realtime events update stores immediately; API refreshes reconcile.

## Auth + Session
- Supabase manages login/session.
- The Supabase access token is attached to all backend requests.
- 401 responses should trigger sign-out and return to login screen.

## Realtime
- Subscribe to `notes`, `websites`, `ingested_files`, `file_processing_jobs` channels.
- Apply realtime events to local stores, then schedule background refreshes.

## Chat Streaming (SSE)
- Support streaming tokens plus UI-side effects (note/website/scratchpad/theme updates).
- Maintain a single active stream per conversation view.

## Tasks (Future Migration)
- Use a `TaskProvider` protocol to separate Things integration from in-app tasks.
- View models depend only on the protocol to ease later migration.
