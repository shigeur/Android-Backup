# Android Backup Architecture

## Application Layers
1. **Presentation Layer (SwiftUI + AppKit):**
   - `AndroidBackupApp.swift`: Main entry point.
   - `ContentView.swift`: Root view managing navigation state.
   - `FileManagerView.swift` & `LocalFileManagerView.swift`: High-level SwiftUI container views.
   - `NativeFileBrowser.swift` & `FileBrowserViewController.swift`: AppKit wrappers providing high-performance file rendering using `NSTableView`.

2. **ViewModel Layer:**
   - `DirectoryViewModel.swift`: State management for Android files.
   - `LocalDirectoryViewModel.swift`: State management for Mac local files.
   - `DeviceManager.swift`: State management for connected ADB devices.
   
3. **Service Layer:**
   - `TransferService.swift`: Handles queued transfer operations (push/pull), calculates ETA, progress, and speeds.
   - `FileOperationService.swift`: Handles deletion, renaming, duplicating.
   - `ClipboardService.swift`: Manages copy/cut state across Android and Mac.

4. **Data Access Layer:**
   - `ADBManager.swift`: Executes underlying `adb` commands synchronously and asynchronously.
   - `DatabaseManager.swift`: GRDB-based SQLite storage for caching files and keeping backup history.
   - `DirectoryCache.swift`: Thread-safe caching layer for directory contents.

## Dependency relationships
- **UI -> ViewModels:** UI components observe ViewModels via `@StateObject` and `@ObservedObject`.
- **ViewModels -> Services:** ViewModels invoke actions on Singletons (`ClipboardService.shared`, `TransferService.shared`, etc.).
- **Services -> ADBManager / Local APIs:** Services map domain actions into raw ADB commands or `FileManager` operations.
- **Services -> Caching:** Successful directory loads and modifications invalidate or update `DirectoryCache` and `DatabaseManager`.
