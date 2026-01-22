# Tasks Renaming Plan

## Scope
Rename all legacy task integration API paths, services, stores, types, UI copy, and tests to Tasks. Remove legacy bridge/diagnostics endpoints and related code.

## Steps
1. Backend: rename legacy router to `tasks`, update paths, config flags, services, and tests.
2. Backend: remove legacy bridge/diagnostics code and any references.
3. Frontend: rename types, API client, store, routes, and UI components to Tasks.
4. Tests: update frontend and backend tests to new names/paths.
5. Verify builds/tests as feasible; delete this plan after completion.
