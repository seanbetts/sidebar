# ``sideBarShared``

Shared networking, configuration, auth, and extension-support primitives used by
the main app and Apple platform extensions.

## Overview

`sideBarShared` centralizes cross-target behavior so iOS/macOS app code, widgets,
and the share extension use the same runtime contracts and error handling.

The module is primarily used for:
- Runtime configuration loading and validation (`API_BASE_URL`, Supabase, and R2 keys).
- API client request/auth/pinning behavior shared by all targets.
- Keychain-backed auth state persistence and extension-safe messaging utilities.

## Topics

### Configuration
- ``EnvironmentConfig``
- ``EnvironmentConfig/load()``
- ``EnvironmentConfigLoadError``
- ``AppGroupConfiguration``

### Networking
- ``APIClientConfig``
- ``APIClientError``
- ``PinnedCertificates``

### Auth
- ``AuthStateStore``
- ``KeychainAuthStateStore``
- ``KeychainError``

### Extensions
- ``ExtensionUserMessageCatalog``
- ``ShareExtensionURLQueueHandler``
- ``ExtensionQueueResultMapper``
