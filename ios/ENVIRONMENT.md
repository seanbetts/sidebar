# iOS Environment Configuration

This app expects the same backend and Supabase setup as the web app.

## Required
- `API_BASE_URL`: Backend base URL (example: `https://api.yourdomain.com/api/v1`)
- `SUPABASE_URL`: Supabase project URL
- `SUPABASE_ANON_KEY`: Supabase anon/public key

## Optional
- `SENTRY_DSN`: if error reporting is enabled in SwiftUI

## Notes
- Values can be injected via Xcode build settings or a local plist.
- Keep secrets out of git; use `.xcconfig` or runtime environment for local dev.
