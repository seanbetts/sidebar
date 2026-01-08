# iOS Permissions Plan

## Location
- Used for weather and places.
- Request only when user enables weather or places features.
- Provide a manual location fallback when denied.

## Photos / Files
- Used for ingestion uploads.
- Use document picker for files; request photo library access only when choosing images.

## Notifications (Future)
- Not required for MVP.
- If added, prompt after user opts into realtime alerts.

## Microphone / Camera
- Not required for MVP.

## Summary
- Defer all permission prompts until needed.
- Provide clear explanation strings in Info.plist.
