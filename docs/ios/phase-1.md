# Phase 1 Checklist (Pre-Xcode + Initial Wiring)

## Pre-Xcode (Complete)
- [x] Repository `ios/` structure created
- [x] Swift DTO scaffolding added
- [x] API/SSE/realtime documentation drafted
- [x] API client extensions + typed service wrappers drafted
- [x] SSE parser + realtime payload stubs added
- [x] SSE URLSession client draft
- [x] View model shells for core domains
- [x] API contract test checklist drafted
- [x] SwiftUI view shells for navigation + sections
- [x] Auth/session stubs and DI container skeleton
- [x] Auth adapter and state store scaffolding
- [x] Navigation state storage keys
- [x] Realtime payload mapping stubs
- [x] Error mapping utility stub
- [x] Cache strategy draft
- [x] Theme model stub

## After Xcode Project Is Added
- [ ] Add Swift files to the Xcode target
- [ ] Wire environment config (API base URL + Supabase keys)
- [ ] Implement Supabase auth sign-in and session restoration
- [ ] Build API client wrappers for core endpoints
- [ ] Implement SSE streaming client (token + UI events)
- [ ] Implement Supabase realtime subscriptions
- [ ] Build minimal shell views + view models to validate routing
- [ ] Verify 401 handling and logout flow
