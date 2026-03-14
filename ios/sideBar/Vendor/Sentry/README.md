# Apple Sentry Vendor Bundle

This directory owns the vendored Apple Sentry SDK used by the Apple app and extension targets that currently link Sentry.

## Source

- Upstream release: `9.7.0`
- Download URL: `https://github.com/getsentry/sentry-cocoa/releases/download/9.7.0/Sentry.xcframework.zip`

## Why this is vendored

The Apple app previously failed to build reliably with Swift Package Manager, and the Carthage prototype also failed for Sentry v9.
For this release cycle, the SDK is checked into the repo as a direct XCFramework so local Xcode, GitHub Actions, and Xcode Cloud all build against the same artifact without package-resolution drift.

## Update process

1. Download the target `Sentry.xcframework.zip` release from Sentry's GitHub releases page.
2. Replace `Sentry.xcframework` in this directory with the new release contents.
3. Update `VERSION`.
4. Re-run the Apple Sentry guardrail and Apple build verification before merging.

## Scope

This vendor path is currently used by the main `sideBar` app target plus the Apple widget, share extension, and Safari extension targets.
