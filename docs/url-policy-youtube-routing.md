# URL Policy: YouTube Routing and Normalization

This project now applies one routing policy for YouTube URLs:

- Generic URL save/share flows treat YouTube URLs as regular websites.
- Only explicit `Add YouTube Video` actions in Files use YouTube ingestion (`/files/youtube`).

## Canonical rule owners

- Backend canonical URL rules:
  - `/Users/sean/Coding/sideBar/backend/api/services/url_normalization_service.py`
- Backend website URL normalization adapter:
  - `/Users/sean/Coding/sideBar/backend/api/services/websites_utils.py`
- Backend YouTube ingestion helper usage:
  - `/Users/sean/Coding/sideBar/backend/api/routers/ingestion_helpers.py`

## Routing by surface

- Web generic website save:
  - `/Users/sean/Coding/sideBar/frontend/src/lib/stores/websites.ts`
- Web explicit Add YouTube flow:
  - `/Users/sean/Coding/sideBar/frontend/src/lib/hooks/useIngestionUploads.ts`
- iOS share extension URL queueing:
  - `/Users/sean/Coding/sideBar/ios/sideBar/ShareExtension/ShareViewController.swift`
- Safari extensions URL queueing (iOS + macOS):
  - `/Users/sean/Coding/sideBar/ios/sideBar/sideBar Safari Extension/SafariWebExtensionHandler.swift`
  - `/Users/sean/Coding/sideBar/ios/sideBar/sideBar Safari Extension (macOS) Extension/SafariWebExtensionHandler.swift`

## Backward compatibility

- Existing queued pending-share items with kind `.youtube` are still consumed by the app:
  - `/Users/sean/Coding/sideBar/ios/sideBar/sideBar/App/AppEnvironment+PendingShares.swift`
