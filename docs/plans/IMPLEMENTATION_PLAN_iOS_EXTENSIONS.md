# iOS Extensions Implementation Plan
**Project:** sideBar iOS App
**Document Version:** 1.0
**Date:** 2026-01-13
**Estimated Total Effort:** 12-16 days

---

## Executive Summary

This document outlines the implementation plan for three high-value iOS features:
1. **Share Sheet Extensions** - Allow users to add content from other apps
2. **Live Upload Notifications** - Real-time upload progress with Dynamic Island
3. **Widgets** - Home screen/lock screen widgets for quick access

All three features leverage existing infrastructure (80%, 70%, and 60% ready respectively) and provide significantly higher user value than alternative architectural changes.

---

## Table of Contents

1. [Prerequisites & Setup](#prerequisites--setup)
2. [Phase 1: Share Extensions (Week 1)](#phase-1-share-extensions-week-1)
3. [Phase 2: Live Upload Notifications (Week 2)](#phase-2-live-upload-notifications-week-2)
4. [Phase 3: Widgets (Weeks 3-4)](#phase-3-widgets-weeks-3-4)
5. [Testing Strategy](#testing-strategy)
6. [Rollout Plan](#rollout-plan)
7. [Success Metrics](#success-metrics)

---

## Prerequisites & Setup

### Required Before Starting

#### 1. App Groups Configuration
**Why:** Extensions need to share data with the main app (auth tokens, pending uploads, cache)

**Steps:**
1. Create App Group identifier in Apple Developer Portal:
   - Recommended: `group.com.yourdomain.sidebar` (replace with actual bundle ID)
2. Add App Groups capability to main app target:
   - Xcode → Target → Signing & Capabilities → + Capability → App Groups
   - Enable the group identifier
3. Add same App Groups capability to each extension target as created

**Files to Update:**
- `sideBar.entitlements` - Add App Groups entitlement
- New: `ShareExtension.entitlements`, `WidgetExtension.entitlements`
**Status:** Complete (app + ShareExtension configured)

#### 2. Push Notification Setup (For Live Activities)
**Why:** Live Activities require push notification capability

**Steps:**
1. Add Push Notifications capability in Xcode:
   - Target → Signing & Capabilities → + Capability → Push Notifications
2. Generate APNS key in Apple Developer Portal:
   - Certificates, Identifiers & Profiles → Keys → + (Create new)
   - Select "Apple Push Notifications service (APNs)"
   - Download .p8 key file and note Key ID
3. Configure backend (if using remote push for activity updates)
4. Request notification permissions in app

**Files to Update:**
- `sideBar.entitlements` - Add push notification entitlement
- New: `NotificationManager.swift` - Handle permission requests

#### 3. Migrate Keychain to Shared Access
**Why:** Share Extension needs to access auth tokens

**Current State:**
- `KeychainAuthStateStore.swift` stores tokens with `kSecAttrAccessGroup: nil`

**Changes Needed:**
```swift
// KeychainAuthStateStore.swift
private let accessGroup = "group.com.yourdomain.sidebar" // Match App Group

private func baseQuery() -> [String: Any] {
  var query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: serviceName
  ]
  // Add access group for shared keychain
  #if !targetEnvironment(simulator)
  query[kSecAttrAccessGroup as String] = accessGroup
  #endif
  return query
}
```

**Files to Update:**
- `KeychainAuthStateStore.swift` - Add access group parameter
**Status:** Complete

#### 4. Core Data Migration to App Groups (For Widgets)
**Why:** Widgets need to read cached data

**Current State:**
- `PersistenceController.swift` uses default container location

**Changes Needed:**
```swift
// PersistenceController.swift
private static func createContainer() -> NSPersistentContainer {
  let container = NSPersistentContainer(name: "CacheModel")

  // Use App Groups container
  if let appGroupURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.com.yourdomain.sidebar"
  ) {
    let storeURL = appGroupURL.appendingPathComponent("sideBar.sqlite")
    let description = NSPersistentStoreDescription(url: storeURL)
    container.persistentStoreDescriptions = [description]
  }

  container.loadPersistentStores { _, error in
    if let error = error {
      fatalError("Core Data failed to load: \(error)")
    }
  }
  return container
}
```

**Files to Update:**
- `PersistenceController.swift` - Update container location

#### 5. Shared UserDefaults
**Why:** Share state between main app and extensions

**Create New File:**
```swift
// SharedUserDefaults.swift
import Foundation

public final class SharedUserDefaults {
  private static let suiteName = "group.com.yourdomain.sidebar"

  public static let shared = UserDefaults(suiteName: suiteName)!

  // Keys
  public enum Keys {
    static let pendingUploads = "pendingUploads"
    static let lastWidgetRefresh = "lastWidgetRefresh"
  }
}
```
**Status:** Complete (share extension uses App Group defaults via `ExtensionEventStore`)

---

## Phase 1: Share Extensions (Week 1)

**Goal:** Allow users to share content from other apps into sideBar
**Effort:** 3-4 days
**Priority:** Highest (80% infrastructure ready)

### Day 1: Foundation & Setup

#### Task 1.1: Create Share Extension Target
**Duration:** 1-2 hours
**Status:** Complete

**Steps:**
1. Xcode → File → New → Target → Share Extension
2. Name: `ShareExtension`
3. Bundle ID: `com.yourdomain.sidebar.ShareExtension`
4. Add to existing group: `sideBar`

**Generated Files:**
- `ShareExtension/ShareViewController.swift`
- `ShareExtension/MainInterface.storyboard`
- `ShareExtension/Info.plist`

**Modify Info.plist:**
```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionAttributes</key>
  <dict>
    <key>NSExtensionActivationRule</key>
    <dict>
      <!-- Accept URLs -->
      <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
      <integer>1</integer>
      <!-- Accept images -->
      <key>NSExtensionActivationSupportsImageWithMaxCount</key>
      <integer>10</integer>
      <!-- Accept files -->
      <key>NSExtensionActivationSupportsFileWithMaxCount</key>
      <integer>10</integer>
      <!-- Accept text -->
      <key>NSExtensionActivationSupportsText</key>
      <true/>
    </dict>
  </dict>
  <key>NSExtensionMainStoryboard</key>
  <string>MainInterface</string>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.share-services</string>
</dict>
```

#### Task 1.2: Add App Groups to Extension
**Duration:** 30 minutes
**Status:** Complete

1. Select ShareExtension target
2. Signing & Capabilities → + Capability → App Groups
3. Enable `group.com.yourdomain.sidebar`
4. Create `ShareExtension.entitlements` (auto-generated)

#### Task 1.3: Share Code Between Targets
**Duration:** 1 hour
**Status:** Complete

**Approach 1: Add files to multiple targets** (Simple, recommended for now)
1. Select these files in Xcode:
   - `Services/Network/APIClient.swift`
   - `Services/Network/IngestionAPI.swift`
   - `Services/Network/WebsitesAPI.swift`
   - `Services/Auth/KeychainAuthStateStore.swift`
   - `Services/Auth/AuthSession.swift`
   - `Models/FileModels.swift`
   - `Models/WebsiteModels.swift`
   - `Utilities/Logger.swift`
2. File Inspector → Target Membership → Enable ShareExtension

**Approach 2: Create Shared Framework** (Better long-term, optional)
- Create `sideBarShared` framework target
- Move shared code there
- Link both main app and extension to framework

**For MVP, use Approach 1** (add files to targets)

#### Task 1.4: Environment Configuration
**Duration:** 1 hour
**Status:** Complete

**Create:** `ShareExtension/ShareExtensionEnvironment.swift`

```swift
import Foundation

@MainActor
final class ShareExtensionEnvironment {
  let apiClient: APIClient
  let ingestionAPI: IngestionAPI
  let websitesAPI: WebsitesAPI
  private let authStore: KeychainAuthStateStore

  init() {
    self.authStore = KeychainAuthStateStore()

    // Get access token from shared keychain
    guard let session = authStore.retrieveSession(),
          let token = session.accessToken else {
      fatalError("Not authenticated - cannot use share extension")
    }

    // Use same API base URL as main app
    let config = EnvironmentConfig.load()
    let baseURL = URL(string: config.apiBaseURL)!

    self.apiClient = APIClient(baseURL: baseURL, accessToken: token)
    self.ingestionAPI = IngestionAPI(client: apiClient)
    self.websitesAPI = WebsitesAPI(client: apiClient)
  }

  var isAuthenticated: Bool {
    authStore.retrieveSession() != nil
  }
}
```

---

### Day 2: Website Sharing Implementation

#### Task 2.1: Extract URL from Share Context
**Duration:** 1 hour

**Modify:** `ShareExtension/ShareViewController.swift`

```swift
import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
  private var environment: ShareExtensionEnvironment!
  private var extractedURL: URL?

  override func viewDidLoad() {
    super.viewDidLoad()

    // Check authentication
    environment = ShareExtensionEnvironment()
    guard environment.isAuthenticated else {
      showError("Please sign in to sideBar first")
      return
    }

    // Extract shared items
    extractSharedContent()
  }

  private func extractSharedContent() {
    guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
          let itemProvider = extensionItem.attachments?.first else {
      showError("No content to share")
      return
    }

    // Check for URL
    if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] (item, error) in
        DispatchQueue.main.async {
          if let url = item as? URL {
            self?.extractedURL = url
            self?.handleURLShare(url)
          } else if let error = error {
            self?.showError("Failed to extract URL: \(error.localizedDescription)")
          }
        }
      }
    }
    // We'll handle files/images in Day 3
  }

  private func handleURLShare(_ url: URL) {
    // Implemented in Task 2.2
  }

  private func showError(_ message: String) {
    let alert = UIAlertController(
      title: "Error",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
      self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    })
    present(alert, animated: true)
  }
}
```

#### Task 2.2: Call Website Quick-Save API
**Duration:** 2 hours

**Add to ShareViewController:**

```swift
private func handleURLShare(_ url: URL) {
  // Show loading UI
  showLoadingView(message: "Saving website...")

  Task {
    do {
      // Call quick-save API
      let response = try await environment.websitesAPI.quickSave(
        url: url.absoluteString,
        title: nil  // Let backend extract title
      )

      // Poll for job completion
      try await pollJobStatus(jobId: response.jobId)

      // Success
      await MainActor.run {
        showSuccessView(message: "Website saved!")

        // Notify main app to refresh
        notifyMainApp(event: "websiteSaved", data: ["jobId": response.jobId])

        // Close extension after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
          self?.extensionContext?.completeRequest(returningItems: nil)
        }
      }
    } catch {
      await MainActor.run {
        showError("Failed to save website: \(error.localizedDescription)")
      }
    }
  }
}

private func pollJobStatus(jobId: String) async throws {
  var attempts = 0
  let maxAttempts = 30  // 30 seconds max

  while attempts < maxAttempts {
    let job = try await environment.websitesAPI.quickSaveStatus(jobId: jobId)

    switch job.status {
    case "completed":
      return  // Success
    case "failed":
      throw NSError(
        domain: "ShareExtension",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: job.errorMessage ?? "Unknown error"]
      )
    case "pending", "processing":
      // Continue polling
      try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
      attempts += 1
    default:
      break
    }
  }

  throw NSError(
    domain: "ShareExtension",
    code: -1,
    userInfo: [NSLocalizedDescriptionKey: "Save timed out"]
  )
}

private func notifyMainApp(event: String, data: [String: Any]) {
  // Use shared UserDefaults to notify main app
  var events = SharedUserDefaults.shared.array(forKey: "extensionEvents") as? [[String: Any]] ?? []
  events.append([
    "event": event,
    "data": data,
    "timestamp": Date().timeIntervalSince1970
  ])
  SharedUserDefaults.shared.set(events, forKey: "extensionEvents")
}
```

#### Task 2.3: Build Simple UI
**Duration:** 2 hours

**Create:** `ShareExtension/Views/LoadingView.swift`

```swift
import UIKit

final class ShareLoadingView: UIView {
  private let activityIndicator = UIActivityIndicatorView(style: .large)
  private let messageLabel = UILabel()

  init(message: String) {
    super.init(frame: .zero)
    setup(message: message)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setup(message: String) {
    backgroundColor = .systemBackground

    activityIndicator.translatesAutoresizingMaskIntoConstraints = false
    activityIndicator.startAnimating()
    addSubview(activityIndicator)

    messageLabel.text = message
    messageLabel.font = .preferredFont(forTextStyle: .headline)
    messageLabel.textColor = .label
    messageLabel.textAlignment = .center
    messageLabel.numberOfLines = 0
    messageLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(messageLabel)

    NSLayoutConstraint.activate([
      activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
      activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),

      messageLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
      messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
    ])
  }
}
```

**Create:** `ShareExtension/Views/SuccessView.swift`

```swift
import UIKit

final class ShareSuccessView: UIView {
  private let checkmarkImageView = UIImageView()
  private let messageLabel = UILabel()

  init(message: String) {
    super.init(frame: .zero)
    setup(message: message)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setup(message: String) {
    backgroundColor = .systemBackground

    checkmarkImageView.image = UIImage(systemName: "checkmark.circle.fill")
    checkmarkImageView.tintColor = .systemGreen
    checkmarkImageView.contentMode = .scaleAspectFit
    checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(checkmarkImageView)

    messageLabel.text = message
    messageLabel.font = .preferredFont(forTextStyle: .headline)
    messageLabel.textColor = .label
    messageLabel.textAlignment = .center
    messageLabel.numberOfLines = 0
    messageLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(messageLabel)

    NSLayoutConstraint.activate([
      checkmarkImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      checkmarkImageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
      checkmarkImageView.widthAnchor.constraint(equalToConstant: 60),
      checkmarkImageView.heightAnchor.constraint(equalToConstant: 60),

      messageLabel.topAnchor.constraint(equalTo: checkmarkImageView.bottomAnchor, constant: 16),
      messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
    ])
  }
}
```

**Add helper methods to ShareViewController:**

```swift
private var currentView: UIView?

private func showLoadingView(message: String) {
  currentView?.removeFromSuperview()
  let loadingView = ShareLoadingView(message: message)
  loadingView.frame = view.bounds
  view.addSubview(loadingView)
  currentView = loadingView
}

private func showSuccessView(message: String) {
  currentView?.removeFromSuperview()
  let successView = ShareSuccessView(message: message)
  successView.frame = view.bounds
  view.addSubview(successView)
  currentView = successView
}
```

---

### Day 3: File & Image Sharing

#### Task 3.1: Extract Files from Share Context
**Duration:** 2 hours

**Add to ShareViewController.extractSharedContent():**

```swift
// After URL check, add:

// Check for images
else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
  itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] (item, error) in
    DispatchQueue.main.async {
      if let url = item as? URL {
        self?.handleFileShare(url)
      } else if let data = item as? Data {
        self?.handleImageData(data)
      } else if let image = item as? UIImage {
        self?.handleImage(image)
      } else if let error = error {
        self?.showError("Failed to extract image: \(error.localizedDescription)")
      }
    }
  }
}

// Check for files
else if itemProvider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
  itemProvider.loadItem(forTypeIdentifier: UTType.item.identifier) { [weak self] (item, error) in
    DispatchQueue.main.async {
      if let url = item as? URL {
        self?.handleFileShare(url)
      } else if let error = error {
        self?.showError("Failed to extract file: \(error.localizedDescription)")
      }
    }
  }
}

else {
  showError("Unsupported content type")
}
```

#### Task 3.2: Upload Files to Backend
**Duration:** 3 hours

**Add to ShareViewController:**

```swift
private func handleFileShare(_ fileURL: URL) {
  showLoadingView(message: "Uploading file...")

  Task {
    do {
      // Read file data
      let data = try Data(contentsOf: fileURL)
      let filename = fileURL.lastPathComponent
      let mimeType = mimeTypeForFile(fileURL)

      // Upload via IngestionAPI
      let response = try await environment.ingestionAPI.upload(
        fileData: data,
        filename: filename,
        mimeType: mimeType,
        folder: nil  // Default folder
      )

      await MainActor.run {
        showSuccessView(message: "File uploaded!")
        notifyMainApp(event: "fileUploaded", data: ["fileId": response.fileId])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
          self?.extensionContext?.completeRequest(returningItems: nil)
        }
      }
    } catch {
      await MainActor.run {
        showError("Upload failed: \(error.localizedDescription)")
      }
    }
  }
}

private func handleImageData(_ data: Data) {
  // Generate filename
  let filename = "image-\(UUID().uuidString).jpg"

  showLoadingView(message: "Uploading image...")

  Task {
    do {
      let response = try await environment.ingestionAPI.upload(
        fileData: data,
        filename: filename,
        mimeType: "image/jpeg",
        folder: nil
      )

      await MainActor.run {
        showSuccessView(message: "Image uploaded!")
        notifyMainApp(event: "fileUploaded", data: ["fileId": response.fileId])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
          self?.extensionContext?.completeRequest(returningItems: nil)
        }
      }
    } catch {
      await MainActor.run {
        showError("Upload failed: \(error.localizedDescription)")
      }
    }
  }
}

private func handleImage(_ image: UIImage) {
  guard let data = image.jpegData(compressionQuality: 0.8) else {
    showError("Failed to process image")
    return
  }
  handleImageData(data)
}

private func mimeTypeForFile(_ url: URL) -> String {
  let ext = url.pathExtension.lowercased()
  switch ext {
  case "jpg", "jpeg": return "image/jpeg"
  case "png": return "image/png"
  case "gif": return "image/gif"
  case "pdf": return "application/pdf"
  case "txt": return "text/plain"
  case "json": return "application/json"
  case "mp4": return "video/mp4"
  case "mov": return "video/quicktime"
  case "mp3": return "audio/mpeg"
  case "wav": return "audio/wav"
  default: return "application/octet-stream"
  }
}
```

---

### Day 4: Polish, Error Handling & Main App Integration

#### Task 4.1: Handle Edge Cases
**Duration:** 2 hours

**Add error scenarios:**

```swift
// Check file size before upload
private func validateFileSize(_ data: Data) throws {
  let maxSize = 100 * 1024 * 1024  // 100MB
  if data.count > maxSize {
    throw NSError(
      domain: "ShareExtension",
      code: -1,
      userInfo: [NSLocalizedDescriptionKey: "File too large (max 100MB)"]
    )
  }
}

// Check authentication before any operation
private func ensureAuthenticated() throws {
  guard environment.isAuthenticated else {
    throw NSError(
      domain: "ShareExtension",
      code: -1,
      userInfo: [NSLocalizedDescriptionKey: "Please sign in to sideBar first"]
    )
  }
}

// Handle network errors
private func handleAPIError(_ error: Error) -> String {
  if let apiError = error as? APIClientError {
    switch apiError {
    case .unauthorized:
      return "Please sign in to sideBar again"
    case .serverError(let statusCode, _):
      return "Server error (\(statusCode))"
    case .networkError:
      return "No internet connection"
    default:
      return apiError.localizedDescription
    }
  }
  return error.localizedDescription
}
```

#### Task 4.2: Main App Event Handling
**Duration:** 2 hours

**Create:** `AppEnvironment+ExtensionEvents.swift` (in main app)

```swift
import Foundation
import Combine

extension AppEnvironment {
  func observeExtensionEvents() {
    // Check for events from Share Extension
    Timer.publish(every: 2.0, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        self?.processExtensionEvents()
      }
      .store(in: &cancellables)
  }

  private func processExtensionEvents() {
    guard let events = SharedUserDefaults.shared.array(forKey: "extensionEvents") as? [[String: Any]],
          !events.isEmpty else {
      return
    }

    // Process each event
    for event in events {
      guard let eventType = event["event"] as? String else { continue }

      switch eventType {
      case "websiteSaved":
        Task {
          await websitesViewModel.load()
          toastCenter.show("Website saved", type: .success)
        }

      case "fileUploaded":
        Task {
          await ingestionViewModel.load()
          toastCenter.show("File uploaded", type: .success)
        }

      default:
        break
      }
    }

    // Clear processed events
    SharedUserDefaults.shared.removeObject(forKey: "extensionEvents")
  }
}
```

**Add to AppEnvironment.init():**

```swift
// Near end of init, after all setup
observeExtensionEvents()
```

#### Task 4.3: Testing & Validation
**Duration:** 2 hours

**Test Cases:**
1. Share URL from Safari → Should save website
2. Share image from Photos → Should upload to Files
3. Share PDF from Files app → Should upload to Files
4. Share while offline → Should show error
5. Share when not authenticated → Should show error
6. Share very large file → Should show error
7. Kill app during share → Should complete in extension
8. Multiple items selected → Should handle first item

**Test Matrix:**

| Source App | Content Type | Expected Result |
|------------|--------------|-----------------|
| Safari | URL | Website saved |
| Photos | Image | File uploaded |
| Files | PDF | File uploaded |
| Notes | Text | (Future: Create note) |
| Safari | Multiple tabs | First URL saved |

---

## Phase 2: Live Upload Notifications (Week 2)

**Goal:** Show real-time upload progress with Live Activities
**Effort:** 4-5 days
**Priority:** High (complements Share Extension)

### Day 5: Push Notification & ActivityKit Setup

#### Task 5.1: Request Notification Permissions
**Duration:** 1 hour

**Create:** `Services/Notifications/NotificationManager.swift`

```swift
import UserNotifications
import UIKit

@MainActor
public final class NotificationManager: NSObject {
  public static let shared = NotificationManager()

  private var isRegistered = false

  private override init() {
    super.init()
  }

  public func requestAuthorization() async throws -> Bool {
    let center = UNUserNotificationCenter.current()

    let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

    if granted {
      await registerForRemoteNotifications()
    }

    return granted
  }

  private func registerForRemoteNotifications() async {
    await UIApplication.shared.registerForRemoteNotifications()
  }

  public func handleDeviceToken(_ deviceToken: Data) {
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("Device token: \(tokenString)")
    // TODO: Send to backend for push notifications
  }

  public func handleNotificationError(_ error: Error) {
    print("Failed to register for notifications: \(error)")
  }
}
```

#### Task 5.2: Update App Delegate
**Duration:** 1 hour

**Modify:** `sideBarApp.swift`

```swift
import SwiftUI
import UserNotifications

@main
struct sideBarApp: App {
  @StateObject private var environment = AppEnvironment(
    container: ServiceContainer.shared
  )
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(environment)
        .task {
          // Request notification permissions on launch
          do {
            let granted = try await NotificationManager.shared.requestAuthorization()
            if granted {
              print("Notification permission granted")
            }
          } catch {
            print("Notification permission error: \(error)")
          }
        }
    }
  }
}

// App Delegate for push notifications
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NotificationManager.shared.handleDeviceToken(deviceToken)
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NotificationManager.shared.handleNotificationError(error)
  }
}
```

#### Task 5.3: Add ActivityKit Framework
**Duration:** 30 minutes

**Steps:**
1. Select main app target
2. General → Frameworks, Libraries, and Embedded Content
3. Click + → Add Other → Add Package Dependency
4. Note: ActivityKit is built into iOS 16.1+, just import it

**Create:** `Services/Notifications/UploadActivityAttributes.swift`

```swift
import ActivityKit
import Foundation

// Define the attributes for upload activity
public struct UploadActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var progress: Double  // 0.0 to 1.0
    var status: String    // "uploading", "processing", "completed", "failed"
    var fileName: String
    var errorMessage: String?
  }

  // Static attributes (don't change during activity)
  var fileId: String
  var fileName: String
  var fileSize: Int64
  var startTime: Date
}
```

---

### Day 6: Live Activity UI Implementation

#### Task 6.1: Design Dynamic Island Views
**Duration:** 3 hours

**Create:** `Views/LiveActivities/UploadLiveActivity.swift`

```swift
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct UploadLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: UploadActivityAttributes.self) { context in
      // Lock screen / banner UI
      UploadActivityLockScreenView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        // Expanded view
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: iconName(for: context.state.status))
            .foregroundColor(iconColor(for: context.state.status))
            .font(.title2)
        }

        DynamicIslandExpandedRegion(.trailing) {
          Text("\(Int(context.state.progress * 100))%")
            .font(.title2.bold())
            .foregroundColor(.primary)
        }

        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 4) {
            Text(context.state.fileName)
              .font(.subheadline.bold())
              .lineLimit(1)

            ProgressView(value: context.state.progress)
              .tint(.blue)
          }
        }

        DynamicIslandExpandedRegion(.bottom) {
          Text(statusMessage(for: context.state))
            .font(.caption)
            .foregroundColor(.secondary)
        }
      } compactLeading: {
        Image(systemName: "arrow.up.circle.fill")
          .foregroundColor(.blue)
      } compactTrailing: {
        ProgressView(value: context.state.progress)
          .tint(.blue)
      } minimal: {
        Image(systemName: "arrow.up.circle.fill")
          .foregroundColor(.blue)
      }
    }
  }

  private func iconName(for status: String) -> String {
    switch status {
    case "completed": return "checkmark.circle.fill"
    case "failed": return "xmark.circle.fill"
    default: return "arrow.up.circle.fill"
    }
  }

  private func iconColor(for status: String) -> Color {
    switch status {
    case "completed": return .green
    case "failed": return .red
    default: return .blue
    }
  }

  private func statusMessage(for state: UploadActivityAttributes.ContentState) -> String {
    switch state.status {
    case "uploading": return "Uploading..."
    case "processing": return "Processing..."
    case "completed": return "Upload complete"
    case "failed": return state.errorMessage ?? "Upload failed"
    default: return ""
    }
  }
}

struct UploadActivityLockScreenView: View {
  let context: ActivityViewContext<UploadActivityAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: "arrow.up.circle.fill")
          .foregroundColor(.blue)
        Text("sideBar")
          .font(.caption.bold())
        Spacer()
        Text("\(Int(context.state.progress * 100))%")
          .font(.caption.bold())
      }

      Text(context.state.fileName)
        .font(.subheadline)
        .lineLimit(1)

      ProgressView(value: context.state.progress)
        .tint(.blue)

      Text(statusMessage(for: context.state))
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding()
  }

  private func statusMessage(for state: UploadActivityAttributes.ContentState) -> String {
    switch state.status {
    case "uploading": return "Uploading..."
    case "processing": return "Processing..."
    case "completed": return "Upload complete"
    case "failed": return state.errorMessage ?? "Upload failed"
    default: return ""
    }
  }
}

@available(iOS 16.1, *)
struct UploadLiveActivity_Previews: PreviewProvider {
  static let attributes = UploadActivityAttributes(
    fileId: "123",
    fileName: "document.pdf",
    fileSize: 1024000,
    startTime: Date()
  )

  static let contentState = UploadActivityAttributes.ContentState(
    progress: 0.5,
    status: "uploading",
    fileName: "document.pdf",
    errorMessage: nil
  )

  static var previews: some View {
    attributes
      .previewContext(contentState, viewKind: .dynamicIsland(.compact))
      .previewDisplayName("Compact")

    attributes
      .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
      .previewDisplayName("Expanded")

    attributes
      .previewContext(contentState, viewKind: .content)
      .previewDisplayName("Lock Screen")
  }
}
```

#### Task 6.2: Register Live Activity Widget
**Duration:** 30 minutes

**Create:** `WidgetBundle` file if needed, or update existing:

**Create:** `UploadWidgetBundle.swift`

```swift
import SwiftUI
import WidgetKit

@main
struct UploadWidgetBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.1, *) {
      UploadLiveActivity()
    }
    // Add other widgets here in Phase 3
  }
}
```

**Update Info.plist:**
```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

---

### Day 7: Live Activity Lifecycle Management

#### Task 7.1: Start Live Activity on Upload
**Duration:** 2 hours

**Create:** `Services/Notifications/LiveActivityManager.swift`

```swift
import ActivityKit
import Foundation

@available(iOS 16.1, *)
@MainActor
public final class LiveActivityManager {
  public static let shared = LiveActivityManager()

  private var activeActivities: [String: Activity<UploadActivityAttributes>] = [:]

  private init() {}

  public func startUploadActivity(
    fileId: String,
    fileName: String,
    fileSize: Int64
  ) async {
    let attributes = UploadActivityAttributes(
      fileId: fileId,
      fileName: fileName,
      fileSize: fileSize,
      startTime: Date()
    )

    let initialState = UploadActivityAttributes.ContentState(
      progress: 0.0,
      status: "uploading",
      fileName: fileName,
      errorMessage: nil
    )

    do {
      let activity = try Activity.request(
        attributes: attributes,
        contentState: initialState,
        pushType: nil  // Or .token for remote push
      )

      activeActivities[fileId] = activity
      print("Started Live Activity for file: \(fileId)")
    } catch {
      print("Failed to start Live Activity: \(error)")
    }
  }

  public func updateProgress(fileId: String, progress: Double, status: String) async {
    guard let activity = activeActivities[fileId] else {
      print("No active activity for file: \(fileId)")
      return
    }

    let updatedState = UploadActivityAttributes.ContentState(
      progress: progress,
      status: status,
      fileName: activity.attributes.fileName,
      errorMessage: nil
    )

    await activity.update(using: updatedState)
  }

  public func completeActivity(fileId: String, success: Bool, errorMessage: String? = nil) async {
    guard let activity = activeActivities[fileId] else {
      print("No active activity for file: \(fileId)")
      return
    }

    let finalState = UploadActivityAttributes.ContentState(
      progress: success ? 1.0 : 0.0,
      status: success ? "completed" : "failed",
      fileName: activity.attributes.fileName,
      errorMessage: errorMessage
    )

    await activity.update(using: finalState)

    // End activity after 3 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
      Task {
        await activity.end(using: finalState, dismissalPolicy: .immediate)
        self.activeActivities.removeValue(forKey: fileId)
      }
    }
  }

  public func cancelActivity(fileId: String) async {
    guard let activity = activeActivities[fileId] else { return }
    await activity.end(dismissalPolicy: .immediate)
    activeActivities.removeValue(forKey: fileId)
  }
}
```

#### Task 7.2: Integrate with IngestionViewModel
**Duration:** 2 hours

**Modify:** `ViewModels/IngestionViewModel.swift`

Add at top:
```swift
#if canImport(ActivityKit)
import ActivityKit
#endif
```

Add method to start tracking:
```swift
private func startLiveActivityForUpload(fileId: String, fileName: String, fileSize: Int64) {
  if #available(iOS 16.1, *) {
    Task {
      await LiveActivityManager.shared.startUploadActivity(
        fileId: fileId,
        fileName: fileName,
        fileSize: fileSize
      )
    }
  }
}

private func updateLiveActivityProgress(fileId: String, progress: Double, status: String) {
  if #available(iOS 16.1, *) {
    Task {
      await LiveActivityManager.shared.updateProgress(
        fileId: fileId,
        progress: progress,
        status: status
      )
    }
  }
}

private func completeLiveActivity(fileId: String, success: Bool, error: String? = nil) {
  if #available(iOS 16.1, *) {
    Task {
      await LiveActivityManager.shared.completeActivity(
        fileId: fileId,
        success: success,
        errorMessage: error
      )
    }
  }
}
```

**Note:** You'll need to hook these into upload flow and realtime job updates

---

### Day 8: Upload Progress Tracking

#### Task 8.1: Add URLSession Progress Delegate
**Duration:** 3 hours

**Modify:** `Services/Network/IngestionAPI.swift`

Add progress callback:
```swift
public func upload(
  fileData: Data,
  filename: String,
  mimeType: String,
  folder: String?,
  progressHandler: ((Double) -> Void)? = nil
) async throws -> IngestionUploadResponse {
  // Create upload task with progress tracking
  let boundary = "Boundary-\(UUID().uuidString)"
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

  let body = createMultipartBody(
    fileData: fileData,
    filename: filename,
    mimeType: mimeType,
    folder: folder,
    boundary: boundary
  )

  // Use URLSession with delegate for progress
  let delegate = UploadProgressDelegate(progressHandler: progressHandler)
  let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

  let (data, response) = try await session.upload(for: request, from: body)

  // Validate response (existing code)
  // ...

  return try JSONDecoder().decode(IngestionUploadResponse.self, from: data)
}
```

**Create delegate class:**
```swift
private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
  let progressHandler: ((Double) -> Void)?

  init(progressHandler: ((Double) -> Void)?) {
    self.progressHandler = progressHandler
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
    DispatchQueue.main.async { [weak self] in
      self?.progressHandler?(progress)
    }
  }
}
```

#### Task 8.2: Connect Progress to Live Activity
**Duration:** 2 hours

**Update IngestionViewModel upload flow:**

```swift
// When starting upload (modify existing upload method)
public func uploadFile(data: Data, filename: String, mimeType: String) async {
  let tempFileId = UUID().uuidString  // Temporary ID until backend returns real one

  // Start Live Activity
  startLiveActivityForUpload(
    fileId: tempFileId,
    fileName: filename,
    fileSize: Int64(data.count)
  )

  do {
    let response = try await api.upload(
      fileData: data,
      filename: filename,
      mimeType: mimeType,
      folder: nil
    ) { [weak self] progress in
      // Update Live Activity with upload progress
      self?.updateLiveActivityProgress(
        fileId: tempFileId,
        progress: progress * 0.7,  // Reserve 30% for processing
        status: "uploading"
      )
    }

    // Upload complete, now processing
    updateLiveActivityProgress(
      fileId: tempFileId,
      progress: 0.7,
      status: "processing"
    )

    // Wait for processing job updates via realtime
    // (handled in applyFileJobEvent)

  } catch {
    completeLiveActivity(fileId: tempFileId, success: false, error: error.localizedDescription)
  }
}
```

---

### Day 9: Realtime Job Status Integration

#### Task 9.1: Connect Realtime Events to Live Activity
**Duration:** 2 hours

**Modify:** `Stores/IngestionStore.swift`

Add callback for job updates:
```swift
public var onJobUpdate: ((String, IngestionJob) -> Void)?

public func applyFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) {
  // Existing code...

  // Notify listeners (for Live Activity)
  if let job = /* extract job from payload */ {
    onJobUpdate?(record.fileId, job)
  }
}
```

**In IngestionViewModel init, observe job updates:**
```swift
store.onJobUpdate = { [weak self] fileId, job in
  self?.handleJobUpdate(fileId: fileId, job: job)
}

private func handleJobUpdate(fileId: String, job: IngestionJob) {
  let progress: Double
  let status: String

  switch job.status {
  case "pending":
    progress = 0.7
    status = "processing"
  case "processing":
    progress = 0.85
    status = "processing"
  case "completed":
    progress = 1.0
    status = "completed"
    completeLiveActivity(fileId: fileId, success: true)
    return
  case "failed":
    completeLiveActivity(fileId: fileId, success: false, error: job.errorMessage)
    return
  default:
    return
  }

  updateLiveActivityProgress(fileId: fileId, progress: progress, status: status)
}
```

#### Task 9.2: Handle Background Updates
**Duration:** 2 hours

**Note:** Live Activities can receive updates even when app is in background via push notifications.

**For MVP:** Realtime connection stays active in foreground. For production, consider:
1. Backend sends push notifications to update activities
2. Use push token from Live Activity
3. Update via APNS priority pushes

**Optional enhancement** (not required for Phase 2):
```swift
// In LiveActivityManager.startUploadActivity
let activity = try Activity.request(
  attributes: attributes,
  contentState: initialState,
  pushType: .token  // Request push token
)

// Get push token
for await pushToken in activity.pushTokenUpdates {
  // Send token to backend
  // Backend can then send updates via APNS
}
```

---

## Phase 3: Widgets (Weeks 3-4)

**Goal:** Home screen and lock screen widgets for quick access
**Effort:** 5-7 days
**Priority:** Medium (most complex, incremental value)

### Day 10: Widget Foundation

#### Task 10.1: Create Widget Extension Target
**Duration:** 1 hour

**Steps:**
1. Xcode → File → New → Target → Widget Extension
2. Name: `sideBarWidget`
3. Include Configuration Intent: Yes (for configurable widgets)
4. Bundle ID: `com.yourdomain.sidebar.sideBarWidget`

**Generated files:**
- `sideBarWidget/sideBarWidget.swift`
- `sideBarWidget/sideBarWidget.intentdefinition`
- `sideBarWidget/Assets.xcassets`

#### Task 10.2: Configure Widget Target
**Duration:** 1 hour

**Add App Groups:**
- Select sideBarWidget target
- Signing & Capabilities → + → App Groups
- Enable `group.com.yourdomain.sidebar`

**Share code with widget:**
1. Select files to share:
   - `Services/Network/APIClient.swift`
   - `Services/Network/ScratchpadAPI.swift`
   - `Services/Network/NotesAPI.swift`
   - `Services/Auth/KeychainAuthStateStore.swift`
   - `Models/ScratchpadModels.swift`
   - `Models/NoteModels.swift`
   - `Services/Cache/CoreDataCacheClient.swift`
   - `Services/Cache/CacheKeys.swift`
2. File Inspector → Target Membership → Enable sideBarWidget

#### Task 10.3: Create Shared Data Manager
**Duration:** 2 hours

**Create:** `Shared/WidgetDataManager.swift`

```swift
import Foundation

@MainActor
public final class WidgetDataManager {
  public static let shared = WidgetDataManager()

  private let apiClient: APIClient
  private let cache: CacheClient

  private init() {
    // Get auth token from shared keychain
    let authStore = KeychainAuthStateStore()
    guard let session = authStore.retrieveSession(),
          let token = session.accessToken else {
      fatalError("Not authenticated")
    }

    let config = EnvironmentConfig.load()
    let baseURL = URL(string: config.apiBaseURL)!

    self.apiClient = APIClient(baseURL: baseURL, accessToken: token)
    self.cache = CoreDataCacheClient.shared
  }

  public func fetchScratchpad() async throws -> ScratchpadContent {
    let api = ScratchpadAPI(client: apiClient)
    let response = try await api.get()

    // Cache for widget refresh
    cache.set(key: CacheKeys.scratchpad, value: response)

    return response
  }

  public func fetchRecentNotes(limit: Int = 5) async throws -> [NoteListItem] {
    let api = NotesAPI(client: apiClient)
    let tree = try await api.getTree()

    // Extract recent notes (flatten tree, sort by updatedAt)
    let allNotes = flattenNoteTree(tree)
    let recent = allNotes
      .sorted { $0.updatedAt > $1.updatedAt }
      .prefix(limit)

    return Array(recent)
  }

  private func flattenNoteTree(_ tree: NoteTree) -> [NoteListItem] {
    var notes: [NoteListItem] = []

    func traverse(_ node: NoteNode) {
      if node.type == "note" {
        notes.append(NoteListItem(
          id: node.id,
          title: node.name,
          updatedAt: node.updatedAt,
          isPinned: node.isPinned
        ))
      }
      node.children?.forEach { traverse($0) }
    }

    tree.roots.forEach { traverse($0) }
    return notes
  }
}

// Simplified models for widgets
public struct NoteListItem: Codable, Identifiable {
  public let id: String
  public let title: String
  public let updatedAt: Date
  public let isPinned: Bool
}
```

---

### Day 11: Scratchpad Widget

#### Task 11.1: Create Scratchpad Timeline Provider
**Duration:** 3 hours

**Create:** `sideBarWidget/ScratchpadWidget.swift`

```swift
import WidgetKit
import SwiftUI

struct ScratchpadEntry: TimelineEntry {
  let date: Date
  let content: String
  let isEmpty: Bool
  let errorMessage: String?
}

struct ScratchpadTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> ScratchpadEntry {
    ScratchpadEntry(
      date: Date(),
      content: "Loading scratchpad...",
      isEmpty: false,
      errorMessage: nil
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (ScratchpadEntry) -> Void) {
    let entry = ScratchpadEntry(
      date: Date(),
      content: "Quick notes and ideas",
      isEmpty: false,
      errorMessage: nil
    )
    completion(entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ScratchpadEntry>) -> Void) {
    Task {
      do {
        let scratchpad = try await WidgetDataManager.shared.fetchScratchpad()

        let entry = ScratchpadEntry(
          date: Date(),
          content: scratchpad.content,
          isEmpty: scratchpad.content.isEmpty,
          errorMessage: nil
        )

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
      } catch {
        let entry = ScratchpadEntry(
          date: Date(),
          content: "",
          isEmpty: true,
          errorMessage: error.localizedDescription
        )

        // Retry in 5 minutes on error
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
      }
    }
  }
}
```

#### Task 11.2: Create Scratchpad Widget Views
**Duration:** 2 hours

**Add to ScratchpadWidget.swift:**

```swift
struct ScratchpadWidgetView: View {
  let entry: ScratchpadEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    ZStack {
      Color(.systemBackground)

      VStack(alignment: .leading, spacing: 8) {
        // Header
        HStack {
          Image(systemName: "note.text")
            .foregroundColor(.blue)
          Text("Scratchpad")
            .font(.subheadline.bold())
          Spacer()
        }

        // Content
        if let error = entry.errorMessage {
          Text(error)
            .font(.caption)
            .foregroundColor(.red)
        } else if entry.isEmpty {
          Text("No notes yet")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          Text(entry.content)
            .font(family == .systemSmall ? .caption : .body)
            .lineLimit(family == .systemSmall ? 4 : 8)
            .foregroundColor(.primary)
        }

        Spacer()
      }
      .padding()
    }
  }
}

struct ScratchpadWidget: Widget {
  let kind: String = "ScratchpadWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ScratchpadTimelineProvider()) { entry in
      ScratchpadWidgetView(entry: entry)
    }
    .configurationDisplayName("Scratchpad")
    .description("Quick access to your scratchpad notes")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
```

---

### Day 12: Recent Notes Widget

#### Task 12.1: Create Notes Timeline Provider
**Duration:** 3 hours

**Create:** `sideBarWidget/RecentNotesWidget.swift`

```swift
import WidgetKit
import SwiftUI

struct RecentNotesEntry: TimelineEntry {
  let date: Date
  let notes: [NoteListItem]
  let errorMessage: String?
}

struct RecentNotesTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> RecentNotesEntry {
    RecentNotesEntry(
      date: Date(),
      notes: [
        NoteListItem(id: "1", title: "Meeting Notes", updatedAt: Date(), isPinned: false),
        NoteListItem(id: "2", title: "Ideas", updatedAt: Date(), isPinned: true),
        NoteListItem(id: "3", title: "To-Do", updatedAt: Date(), isPinned: false)
      ],
      errorMessage: nil
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (RecentNotesEntry) -> Void) {
    completion(placeholder(in: context))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<RecentNotesEntry>) -> Void) {
    Task {
      do {
        let notes = try await WidgetDataManager.shared.fetchRecentNotes(limit: 5)

        let entry = RecentNotesEntry(
          date: Date(),
          notes: notes,
          errorMessage: nil
        )

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
      } catch {
        let entry = RecentNotesEntry(
          date: Date(),
          notes: [],
          errorMessage: error.localizedDescription
        )

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
      }
    }
  }
}
```

#### Task 12.2: Create Notes Widget Views
**Duration:** 2 hours

```swift
struct RecentNotesWidgetView: View {
  let entry: RecentNotesEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    ZStack {
      Color(.systemBackground)

      VStack(alignment: .leading, spacing: 8) {
        // Header
        HStack {
          Image(systemName: "note.text")
            .foregroundColor(.blue)
          Text("Recent Notes")
            .font(.subheadline.bold())
          Spacer()
        }
        .padding(.horizontal)
        .padding(.top)

        // Content
        if let error = entry.errorMessage {
          Text(error)
            .font(.caption)
            .foregroundColor(.red)
            .padding(.horizontal)
        } else if entry.notes.isEmpty {
          Text("No notes yet")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
        } else {
          VStack(spacing: 4) {
            ForEach(entry.notes.prefix(displayLimit)) { note in
              Link(destination: deepLink(for: note)) {
                NoteRowView(note: note)
              }
            }
          }
        }

        Spacer()
      }
      .padding(.bottom)
    }
  }

  private var displayLimit: Int {
    switch family {
    case .systemSmall: return 3
    case .systemMedium: return 3
    case .systemLarge: return 5
    default: return 5
    }
  }

  private func deepLink(for note: NoteListItem) -> URL {
    // Use simple notification-style routing (not full URL schema)
    URL(string: "sidebar://notes/\(note.id)")!
  }
}

struct NoteRowView: View {
  let note: NoteListItem

  var body: some View {
    HStack(spacing: 8) {
      if note.isPinned {
        Image(systemName: "pin.fill")
          .font(.caption2)
          .foregroundColor(.yellow)
      }

      Text(note.title)
        .font(.caption)
        .foregroundColor(.primary)
        .lineLimit(1)

      Spacer()

      Text(relativeTime(note.updatedAt))
        .font(.caption2)
        .foregroundColor(.secondary)
    }
    .padding(.horizontal)
    .padding(.vertical, 4)
  }

  private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}

struct RecentNotesWidget: Widget {
  let kind: String = "RecentNotesWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: RecentNotesTimelineProvider()) { entry in
      RecentNotesWidgetView(entry: entry)
    }
    .configurationDisplayName("Recent Notes")
    .description("Quick access to your recent notes")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
```

---

### Day 13-14: Tasks Widget (Requires Backend)

#### Task 13.1: Implement Tasks API (Backend)
**Duration:** 4-6 hours**

**Required Backend Endpoints:**
```
GET /api/v1/tasks
  Response: { tasks: [{ id, title, completed, dueDate, createdAt }] }

POST /api/v1/tasks
  Body: { title, dueDate? }
  Response: { task: { id, ... } }

PATCH /api/v1/tasks/:id
  Body: { completed?, title?, dueDate? }
  Response: { task: { id, ... } }

DELETE /api/v1/tasks/:id
  Response: 204
```

**Note:** This is outside iOS scope. Coordinate with backend team.

#### Task 13.2: Implement Tasks API Client (iOS)
**Duration:** 2 hours

**Create:** `Services/Network/TasksAPI.swift`

```swift
import Foundation

public protocol TasksProviding {
  func list() async throws -> TasksListResponse
  func create(title: String, dueDate: Date?) async throws -> TaskItem
  func update(id: String, completed: Bool?, title: String?, dueDate: Date?) async throws -> TaskItem
  func delete(id: String) async throws
}

public final class TasksAPI: TasksProviding {
  private let client: APIClient

  public init(client: APIClient) {
    self.client = client
  }

  public func list() async throws -> TasksListResponse {
    try await client.get(path: "/tasks")
  }

  public func create(title: String, dueDate: Date?) async throws -> TaskItem {
    let body: [String: Any] = [
      "title": title,
      "due_date": dueDate?.ISO8601Format() as Any
    ]
    let response: TaskCreateResponse = try await client.post(path: "/tasks", body: body)
    return response.task
  }

  public func update(
    id: String,
    completed: Bool?,
    title: String?,
    dueDate: Date?
  ) async throws -> TaskItem {
    var body: [String: Any] = [:]
    if let completed = completed { body["completed"] = completed }
    if let title = title { body["title"] = title }
    if let dueDate = dueDate { body["due_date"] = dueDate.ISO8601Format() }

    let response: TaskUpdateResponse = try await client.patch(path: "/tasks/\(id)", body: body)
    return response.task
  }

  public func delete(id: String) async throws {
    try await client.delete(path: "/tasks/\(id)")
  }
}
```

**Create:** `Models/TaskModels.swift`

```swift
import Foundation

public struct TasksListResponse: Codable {
  public let tasks: [TaskItem]
}

public struct TaskItem: Codable, Identifiable {
  public let id: String
  public let title: String
  public let completed: Bool
  public let dueDate: Date?
  public let createdAt: Date
  public let updatedAt: Date
}

public struct TaskCreateResponse: Codable {
  public let task: TaskItem
}

public struct TaskUpdateResponse: Codable {
  public let task: TaskItem
}
```

#### Task 13.3: Implement TasksViewModel
**Duration:** 2 hours

**Update:** `ViewModels/TasksViewModel.swift` (currently stub)

```swift
import Foundation
import Combine

@MainActor
public final class TasksViewModel: ObservableObject {
  @Published public private(set) var tasks: [TaskItem] = []
  @Published public private(set) var isLoading: Bool = false
  @Published public private(set) var errorMessage: String?

  private let api: TasksAPI
  private let cache: CacheClient

  public init(api: TasksAPI, cache: CacheClient) {
    self.api = api
    self.cache = cache
  }

  public func load() async {
    isLoading = true
    errorMessage = nil

    // Try cache first
    if let cached: TasksListResponse = cache.get(key: CacheKeys.tasksList) {
      tasks = cached.tasks
    }

    do {
      let response = try await api.list()
      tasks = response.tasks
      cache.set(key: CacheKeys.tasksList, value: response)
    } catch {
      if tasks.isEmpty {
        errorMessage = error.localizedDescription
      }
    }

    isLoading = false
  }

  public func toggleComplete(id: String) async {
    guard let task = tasks.first(where: { $0.id == id }) else { return }

    // Optimistic update
    if let index = tasks.firstIndex(where: { $0.id == id }) {
      var updated = task
      updated = TaskItem(
        id: task.id,
        title: task.title,
        completed: !task.completed,
        dueDate: task.dueDate,
        createdAt: task.createdAt,
        updatedAt: Date()
      )
      tasks[index] = updated
    }

    do {
      _ = try await api.update(id: id, completed: !task.completed, title: nil, dueDate: nil)
      await load()  // Refresh from server
    } catch {
      // Revert on error
      await load()
      errorMessage = error.localizedDescription
    }
  }

  public func delete(id: String) async {
    do {
      try await api.delete(id: id)
      tasks.removeAll { $0.id == id }
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
```

#### Task 13.4: Create Tasks Widget
**Duration:** 3 hours

**Create:** `sideBarWidget/TasksWidget.swift`

```swift
import WidgetKit
import SwiftUI
import AppIntents

struct TasksEntry: TimelineEntry {
  let date: Date
  let tasks: [TaskItem]
  let errorMessage: String?
}

struct TasksTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> TasksEntry {
    TasksEntry(
      date: Date(),
      tasks: [
        TaskItem(id: "1", title: "Example task", completed: false, dueDate: nil, createdAt: Date(), updatedAt: Date())
      ],
      errorMessage: nil
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
    completion(placeholder(in: context))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
    Task {
      do {
        let tasksAPI = TasksAPI(client: /* shared APIClient */)
        let response = try await tasksAPI.list()

        let entry = TasksEntry(
          date: Date(),
          tasks: response.tasks.filter { !$0.completed },  // Only show incomplete
          errorMessage: nil
        )

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
      } catch {
        let entry = TasksEntry(date: Date(), tasks: [], errorMessage: error.localizedDescription)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

        completion(timeline)
      }
    }
  }
}

struct TasksWidgetView: View {
  let entry: TasksEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    ZStack {
      Color(.systemBackground)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: "checkmark.circle")
            .foregroundColor(.blue)
          Text("Tasks")
            .font(.subheadline.bold())
          Spacer()
          Text("\(entry.tasks.count)")
            .font(.caption.bold())
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top)

        if let error = entry.errorMessage {
          Text(error)
            .font(.caption)
            .foregroundColor(.red)
            .padding(.horizontal)
        } else if entry.tasks.isEmpty {
          Text("No tasks")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
        } else {
          VStack(spacing: 4) {
            ForEach(entry.tasks.prefix(displayLimit)) { task in
              TaskRowView(task: task)
            }
          }
        }

        Spacer()
      }
      .padding(.bottom)
    }
  }

  private var displayLimit: Int {
    switch family {
    case .systemSmall: return 3
    case .systemMedium: return 4
    case .systemLarge: return 6
    default: return 6
    }
  }
}

struct TaskRowView: View {
  let task: TaskItem

  var body: some View {
    Button(intent: ToggleTaskIntent(taskId: task.id)) {
      HStack(spacing: 8) {
        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
          .foregroundColor(task.completed ? .green : .secondary)
          .font(.body)

        Text(task.title)
          .font(.caption)
          .foregroundColor(.primary)
          .lineLimit(1)
          .strikethrough(task.completed)

        Spacer()

        if let dueDate = task.dueDate {
          Text(dueDate, style: .date)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
  }
}

// App Intent for interactive widget
struct ToggleTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Toggle Task"

  @Parameter(title: "Task ID")
  var taskId: String

  func perform() async throws -> some IntentResult {
    // Call API to toggle task
    // This requires setting up shared API client accessible from widget
    return .result()
  }
}

struct TasksWidget: Widget {
  let kind: String = "TasksWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: TasksTimelineProvider()) { entry in
      TasksWidgetView(entry: entry)
    }
    .configurationDisplayName("Tasks")
    .description("Quick access to your tasks")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
```

---

### Day 15: Widget Polish & Background Refresh

#### Task 15.1: Implement Background Refresh
**Duration:** 3 hours

**Create:** `App/BackgroundRefreshManager.swift` (in main app)

```swift
import BackgroundTasks
import UIKit

@MainActor
public final class BackgroundRefreshManager {
  public static let shared = BackgroundRefreshManager()

  private let taskIdentifier = "com.yourdomain.sidebar.refresh"

  private init() {}

  public func register() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: taskIdentifier,
      using: nil
    ) { task in
      self.handleAppRefresh(task: task as! BGAppRefreshTask)
    }
  }

  public func scheduleRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // 15 minutes

    do {
      try BGTaskScheduler.shared.submit(request)
      print("Background refresh scheduled")
    } catch {
      print("Failed to schedule background refresh: \(error)")
    }
  }

  private func handleAppRefresh(task: BGAppRefreshTask) {
    scheduleRefresh()  // Reschedule

    Task {
      do {
        // Refresh widget data
        try await WidgetDataManager.shared.fetchScratchpad()
        try await WidgetDataManager.shared.fetchRecentNotes()

        // Tell WidgetKit to reload
        WidgetCenter.shared.reloadAllTimelines()

        task.setTaskCompleted(success: true)
      } catch {
        task.setTaskCompleted(success: false)
      }
    }
  }
}
```

**Update Info.plist:**
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>com.yourdomain.sidebar.refresh</string>
</array>
```

**In sideBarApp.swift, register on launch:**
```swift
init() {
  BackgroundRefreshManager.shared.register()
}

var body: some Scene {
  WindowGroup {
    ContentView()
      .environmentObject(environment)
      .task {
        BackgroundRefreshManager.shared.scheduleRefresh()
      }
  }
}
```

#### Task 15.2: Widget Deep Link Handling
**Duration:** 2 hours

**In main app, add URL handler:**

**Create:** `App/DeepLinkHandler.swift`

```swift
import Foundation

@MainActor
final class DeepLinkHandler {
  private let environment: AppEnvironment

  init(environment: AppEnvironment) {
    self.environment = environment
  }

  func handle(_ url: URL) {
    guard url.scheme == "sidebar" else { return }

    let components = url.pathComponents.filter { $0 != "/" }
    guard components.count >= 2 else { return }

    let section = components[0]
    let id = components[1]

    Task {
      switch section {
      case "notes":
        await environment.notesViewModel.selectNote(id: id)
        environment.commandSelection = .notes

      case "chats":
        await environment.chatViewModel.selectConversation(id: id)
        environment.commandSelection = .chat

      case "websites":
        await environment.websitesViewModel.selectWebsite(id: id)
        environment.commandSelection = .websites

      case "files":
        await environment.ingestionViewModel.selectFile(fileId: id)
        environment.commandSelection = .files

      case "tasks":
        // Navigate to tasks section
        environment.commandSelection = .tasks

      default:
        break
      }
    }
  }
}
```

**In ContentView, add handler:**
```swift
.onOpenURL { url in
  DeepLinkHandler(environment: environment).handle(url)
}
```

#### Task 15.3: Lock Screen Widgets (iOS 16+)
**Duration:** 2 hours

**Add lock screen support to widgets:**

```swift
// In each widget configuration, add:
.supportedFamilies([
  .systemSmall,
  .systemMedium,
  .systemLarge,
  .accessoryCircular,      // Lock screen circular
  .accessoryRectangular,   // Lock screen rectangular
  .accessoryInline         // Lock screen inline
])
```

**Create lock screen views:**

```swift
// In each widget view, add cases for lock screen families:

@ViewBuilder
var body: some View {
  switch family {
  case .accessoryCircular:
    CircularLockScreenView(entry: entry)
  case .accessoryRectangular:
    RectangularLockScreenView(entry: entry)
  case .accessoryInline:
    InlineLockScreenView(entry: entry)
  default:
    MainWidgetView(entry: entry)
  }
}

struct CircularLockScreenView: View {
  let entry: ScratchpadEntry

  var body: some View {
    ZStack {
      AccessoryWidgetBackground()
      VStack {
        Image(systemName: "note.text")
        Text(entry.isEmpty ? "0" : "✓")
          .font(.caption2)
      }
    }
  }
}
```

---

## Testing Strategy

### Unit Testing

**Share Extension:**
- Test URL extraction from NSExtensionItem
- Test file data extraction
- Test API calls with mock responses
- Test error handling paths

**Live Activities:**
- Test activity lifecycle (start, update, end)
- Test progress calculations
- Test realtime event handling
- Mock ActivityKit for simulator testing

**Widgets:**
- Test timeline generation
- Test data fetching and caching
- Test error states
- Test different widget sizes

### Integration Testing

**Share Extension:**
1. Share URL from Safari → Verify in main app
2. Share image from Photos → Check Files section
3. Share while offline → Error displayed
4. Share when logged out → Error displayed
5. Multiple uploads → All succeed

**Live Activities:**
1. Upload file → Activity appears
2. Progress updates → Activity reflects changes
3. App backgrounded → Activity continues
4. Upload completes → Activity dismisses
5. Upload fails → Error shown

**Widgets:**
1. Add widget → Data loads
2. Tap widget item → App opens to item
3. Background refresh → Data updates
4. Logged out → Error state shown
5. Offline → Cached data shown

### Manual Testing Checklist

**Phase 1 (Share Extension):**
- [ ] Share URL from Safari
- [ ] Share image from Photos
- [ ] Share PDF from Files app
- [ ] Share text (if implemented)
- [ ] Test while offline
- [ ] Test while not authenticated
- [ ] Test with large file (100MB+)
- [ ] Test main app refresh after share
- [ ] Test multiple rapid shares

**Phase 2 (Live Activities):**
- [ ] Upload triggers Live Activity
- [ ] Dynamic Island compact view
- [ ] Dynamic Island expanded view
- [ ] Lock screen Live Activity
- [ ] Progress bar updates
- [ ] Success state
- [ ] Error state
- [ ] App backgrounded during upload
- [ ] Multiple concurrent uploads

**Phase 3 (Widgets):**
- [ ] Add Scratchpad widget (small, medium)
- [ ] Add Recent Notes widget (all sizes)
- [ ] Add Tasks widget (all sizes)
- [ ] Tap widget opens app
- [ ] Background refresh works
- [ ] Lock screen widgets (iOS 16+)
- [ ] Widget updates when app changes data
- [ ] Error states display correctly

---

## Rollout Plan

### Week 1: Share Extension Beta
**Goal:** Get Share Extension in users' hands quickly

**Day 1-4:** Implement Share Extension (Phase 1)
**Day 5:** Internal testing
**Day 6-7:** Beta release via TestFlight

**Success Criteria:**
- 50+ shares from beta testers
- <5% error rate
- Positive feedback on UX

### Week 2: Live Activities Release
**Goal:** Polish upload experience

**Day 8-9:** Implement Live Activities (Phase 2)
**Day 10:** Internal testing on iPhone 14 Pro+ (Dynamic Island)
**Day 11-12:** Beta release with Share Extension
**Day 13-14:** Monitor usage and fix bugs

**Success Criteria:**
- Live Activity appears for 90%+ of uploads
- Users complete upload before dismissing activity
- No crashes or ANRs

### Week 3-4: Widgets Rollout
**Goal:** Incremental widget launches

**Week 3 Day 1-2:** Scratchpad widget beta
**Week 3 Day 3-4:** Recent Notes widget beta
**Week 3 Day 5:** Full beta release (Share + Live Activities + 2 widgets)

**Week 4 Day 1-2:** Tasks API implementation (backend + iOS)
**Week 4 Day 3-4:** Tasks widget beta
**Week 4 Day 5:** Polish and bug fixes
**Week 4 Weekend:** Production release!

### Production Release (End of Week 4)
**Includes:**
- Share Extension (URLs, images, files)
- Live Upload Activities
- Scratchpad Widget
- Recent Notes Widget
- Tasks Widget
- Lock screen widget support

---

## Success Metrics

### Share Extension
**Target Metrics:**
- **Adoption:** 30% of users share content within first week
- **Volume:** 5+ shares per active user per week
- **Success Rate:** >95% of shares complete successfully
- **Speed:** <5 seconds for URL save, <30 seconds for file upload

**Tracking:**
- Log share events to analytics
- Track source app (Safari, Photos, etc.)
- Monitor error rates by type
- A/B test success messaging

### Live Activities
**Target Metrics:**
- **Engagement:** 80%+ of users with iOS 16.1+ see activities
- **Completion:** 90%+ of activities show success state
- **Satisfaction:** Users rate upload experience 4.5+/5

**Tracking:**
- Activity start/end events
- Time from start to completion
- Error rates
- User surveys on upload experience

### Widgets
**Target Metrics:**
- **Adoption:** 40% of users add at least one widget
- **Retention:** 70% of widget users keep it after 1 week
- **Engagement:** 2+ widget taps per user per day
- **Refresh Success:** >90% of timeline refreshes succeed

**Tracking:**
- Widget install events by type
- Widget tap events (deep links)
- Background refresh success rates
- Most popular widget sizes

---

## Risk Mitigation

### Risk: Authentication in Extensions
**Issue:** Share Extension/Widgets can't access main app's auth without shared keychain

**Mitigation:**
- Migrate to App Groups keychain early (Day 1)
- Test auth flow in extension before building features
- Add "Sign in to use this feature" error state
- Document keychain access issues clearly

### Risk: Background Upload Reliability
**Issue:** iOS may kill extension before upload completes

**Mitigation:**
- Use URLSession background configuration
- Store pending uploads in shared UserDefaults
- Retry failed uploads in main app
- Show clear error states to user

### Risk: Widget Data Staleness
**Issue:** Widgets show old data if background refresh fails

**Mitigation:**
- Cache data with timestamps
- Show "Last updated X ago" in widget
- Use aggressive caching (15min TTL)
- Fallback to cached data on error

### Risk: Dynamic Island Complexity
**Issue:** Many devices don't support Dynamic Island (only iPhone 14 Pro+)

**Mitigation:**
- Design works on lock screen for all devices
- Test on non-Dynamic Island devices extensively
- Use iOS feature availability checks
- Provide good fallback experience

### Risk: Tasks API Dependency
**Issue:** Tasks widget blocked on backend implementation

**Mitigation:**
- Ship Scratchpad and Notes widgets first (Week 3)
- Coordinate with backend early (Week 1)
- Tasks widget is nice-to-have, not MVP
- Can ship other widgets without Tasks

---

## Appendix: File Structure

```
sideBar/
├── sideBar/                          # Main app
│   ├── App/
│   │   ├── sideBarApp.swift          # Modified: Add notification setup
│   │   ├── AppEnvironment.swift       # Modified: Add extension event observer
│   │   ├── AppDelegate.swift          # New: Push notification delegate
│   │   └── DeepLinkHandler.swift      # New: Handle widget deep links
│   ├── Services/
│   │   ├── Network/
│   │   │   ├── IngestionAPI.swift     # Modified: Add progress handler
│   │   │   ├── TasksAPI.swift         # New: Tasks API client
│   │   ├── Notifications/
│   │   │   ├── NotificationManager.swift        # New: Permission handling
│   │   │   ├── LiveActivityManager.swift        # New: Activity lifecycle
│   │   │   └── UploadActivityAttributes.swift   # New: Activity definition
│   │   └── Auth/
│   │       └── KeychainAuthStateStore.swift     # Modified: Shared keychain
│   ├── Models/
│   │   └── TaskModels.swift           # New: Task data models
│   ├── ViewModels/
│   │   ├── IngestionViewModel.swift   # Modified: Integrate Live Activities
│   │   └── TasksViewModel.swift       # New: Tasks state management
│   ├── Views/
│   │   └── LiveActivities/
│   │       └── UploadLiveActivity.swift  # New: Live Activity UI
│   ├── Utilities/
│   │   └── SharedUserDefaults.swift   # New: Cross-target defaults
│   └── sideBar.entitlements           # Modified: Add App Groups, Push
│
├── ShareExtension/                    # New target
│   ├── ShareViewController.swift      # Share UI controller
│   ├── ShareExtensionEnvironment.swift # Dependency injection
│   ├── Views/
│   │   ├── LoadingView.swift
│   │   └── SuccessView.swift
│   ├── Info.plist                     # Activation rules
│   └── ShareExtension.entitlements    # App Groups
│
├── sideBarWidget/                     # New target
│   ├── sideBarWidget.swift            # Widget bundle
│   ├── ScratchpadWidget.swift         # Scratchpad widget
│   ├── RecentNotesWidget.swift        # Notes widget
│   ├── TasksWidget.swift              # Tasks widget
│   ├── WidgetDataManager.swift        # Shared data fetching
│   └── sideBarWidget.entitlements     # App Groups
│
└── Shared/                            # New group
    ├── WidgetDataManager.swift        # Widget data layer
    └── Models/
        └── NoteListItem.swift         # Simplified models for widgets
```

---

## Appendix: Required Entitlements

### Main App (`sideBar.entitlements`)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.developer.associated-domains</key>
  <array>
    <string>applinks:yourdomain.com</string>
  </array>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.com.yourdomain.sidebar</string>
  </array>
  <key>aps-environment</key>
  <string>development</string>
  <key>keychain-access-groups</key>
  <array>
    <string>$(AppIdentifierPrefix)group.com.yourdomain.sidebar</string>
  </array>
</dict>
</plist>
```

### Share Extension (`ShareExtension.entitlements`)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.com.yourdomain.sidebar</string>
  </array>
  <key>keychain-access-groups</key>
  <array>
    <string>$(AppIdentifierPrefix)group.com.yourdomain.sidebar</string>
  </array>
</dict>
</plist>
```

### Widget Extension (`sideBarWidget.entitlements`)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.com.yourdomain.sidebar</string>
  </array>
  <key>keychain-access-groups</key>
  <array>
    <string>$(AppIdentifierPrefix)group.com.yourdomain.sidebar</string>
  </array>
</dict>
</plist>
```

---

## Conclusion

This implementation plan provides a comprehensive, step-by-step guide to building three high-value iOS features: Share Extensions, Live Upload Notifications, and Widgets. By following this plan, you'll deliver significant user value while leveraging your existing infrastructure.

**Key Takeaways:**
- **Week 1:** Share Extension (quick win, high impact)
- **Week 2:** Live Activities (polish, leverages Share Extension)
- **Weeks 3-4:** Widgets (incremental, high visibility)

Total effort: **12-16 days** of focused development.

**Next Steps:**
1. Review and approve plan
2. Set up prerequisites (App Groups, Push certs)
3. Begin Phase 1: Share Extension

Good luck! 🚀
