# iOS Architecture

This document summarizes the SwiftUI app architecture for sideBar, including the data flow, service boundaries, and testing approach.

## Overview

The iOS app follows an MVVM-style architecture with clear separation between UI, state, and side-effecting services:

- **Views** render SwiftUI screens and forward user intent to ViewModels.
- **ViewModels** orchestrate UI state and call Stores/Services for data.
- **Stores** hold cached state and coordinate updates from services.
- **Services** encapsulate business logic and external integrations (network, cache, realtime, auth).
- **Utilities** provide shared helpers (formatting, parsing, validation).

## Module Layout

- `ios/sideBar/sideBar/App/`
  - App entry points, dependency injection, and environment configuration.
- `ios/sideBar/sideBar/ViewModels/`
  - Feature-specific ViewModels that publish UI state.
- `ios/sideBar/sideBar/Stores/`
  - Cached state containers used by ViewModels.
- `ios/sideBar/sideBar/Services/`
  - Business logic and integrations (API, auth, cache, realtime, upload).
- `ios/sideBar/sideBar/Views/`
  - SwiftUI screens and reusable components.
- `ios/sideBar/sideBar/Utilities/`
  - Formatting, parsing, validation, and shared helpers.

## Data Flow

1. **View** captures input and calls a ViewModel.
2. **ViewModel** updates local state and delegates to a Store or Service.
3. **Store** fetches data through Services and publishes updates.
4. **ViewModel** observes Store changes and updates published state.
5. **View** renders updates reactively.

This keeps side effects and networking in Services while UI logic stays within ViewModels.

## Streaming & Realtime

- **Streaming chat** uses the streaming service pattern in `Services/Chat/` and delivers token updates to ViewModels for incremental UI updates.
- **Realtime updates** are handled by `Services/Realtime/` with adapters that emit changes to Stores, keeping ViewModels in sync.

## Caching & Persistence

- **Core Data** is the primary persistence mechanism, wrapped behind cache services in `Services/Cache/`.
- **Stores** mediate cache consistency and expose the latest state to ViewModels.

## Configuration & Dependency Injection

- `AppEnvironment` builds the dependency graph and provides service instances.
- Environment configuration is sourced from `.xcconfig` values, including `SideBar.local.xcconfig` for local overrides.

## Testing Approach

- **Unit tests** live in `ios/sideBar/sideBarTests/` and focus on ViewModels, Stores, and Services.
- **API tests** rely on URLProtocol stubs and mock providers.
- **Utilities** have dedicated coverage for parsing, formatting, and validation logic.

## Related Docs

- Project overview: `README.md`
- Local setup: `docs/LOCAL_DEVELOPMENT.md`
