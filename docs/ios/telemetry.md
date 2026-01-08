# iOS Telemetry Plan (Optional)

## Goals
- Track crash-free sessions
- Capture client-side errors and API failures

## Recommendation
- Use Sentry (matches web app)
- Enable only after MVP stability

## Events
- App launch
- Auth failures
- SSE errors
- Realtime disconnects
- Upload failures

## Notes
- Avoid sending PII in breadcrumbs
- Respect user privacy settings
