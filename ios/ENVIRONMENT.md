# iOS Environment Configuration

Canonical source of truth:
- `/Users/sean/Coding/sideBar/docs/IOS_ENGINEERING_HANDBOOK.md`

This file keeps a focused reference for environment keys and local setup.

The Apple app and extensions require runtime configuration from build settings
(`.xcconfig`) that is exposed via Info.plist keys.

## Required Keys
- `API_BASE_URL`: backend base URL (for example `http://127.0.0.1:8001/api/v1` for local).
- `SUPABASE_URL`: Supabase project URL.
- `SUPABASE_ANON_KEY`: Supabase anon/public key.
- `APP_GROUP_ID`: app group identifier shared by app/extensions.
- `KEYCHAIN_ACCESS_GROUP`: keychain access group used for shared auth state.
- `KEYCHAIN_SERVICE`: keychain service name.
- `ASSOCIATED_DOMAINS`: Apple Associated Domains entitlement entries (for example `webcredentials:sidebar.seanbetts.com`).
- `R2_ENDPOINT`: Cloudflare R2 S3 endpoint.
- `R2_BUCKET`: R2 bucket for ingestion uploads.
- `R2_FAVICON_BUCKET`: R2 bucket for favicon assets.
- `R2_FAVICON_PUBLIC_BASE_URL`: public base URL for favicon delivery.

## Local Setup
1. Copy `/Users/sean/Coding/sideBar/ios/sideBar/Config/SideBar.local.xcconfig.example`
   to `SideBar.local.xcconfig`.
2. Fill in all required keys.
3. Ensure the project uses `/Users/sean/Coding/sideBar/ios/sideBar/Config/SideBar.xcconfig`
   (it includes the local override file).

## CI / Xcode Cloud
- `/Users/sean/Coding/sideBar/ios/sideBar/ci_scripts/ci_post_clone.sh`
  generates `SideBar.local.xcconfig` from environment variables.
- Missing required config values fail fast.

## Important Behavior
- Non-production builds do not silently fall back to production API URLs.
- If required keys are missing or invalid at runtime, config load fails and the app shows
  a configuration error state.
