# Android Backup (Native macOS App)

This is a native macOS application built with SwiftUI for managing and backing up Android devices over ADB without requiring MTP.

## Prerequisites
- macOS 13.0 or higher
- Xcode 16.0 or higher
- Apple Silicon (or Intel)

## How to Build and Run in Xcode

1. Double click `AndroidBackup.xcodeproj` to open it in Xcode.
2. Select the **AndroidBackup** scheme in the top toolbar (next to the play button).
3. Select **My Mac** as the destination.
4. Press `Cmd + R` or click the **Play** button to build and run the application.

## Troubleshooting Sandbox Permissions

If the ADB Connection Diagnostics page reports that the `adb` executable cannot be launched due to the sandbox:
1. Ensure that the `adb` executable has been manually selected using the "Browse..." button in the Settings page. This registers a Security Scoped Bookmark.
2. Because this project is fully sandboxed, it utilizes the `com.apple.security.files.user-selected.executable` entitlement to allow executing the binary. This is configured automatically in `Entitlements.plist`.
