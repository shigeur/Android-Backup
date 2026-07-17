# BASELINE: Beta-1 Stable Baseline

## Application Version
Beta-1

## Architecture Overview
The application uses a hybrid SwiftUI and AppKit architecture. SwiftUI is used for the overall application structure, layout (Dual Pane, Sidebar, Toolbars), and auxiliary views (Transfer Progress, Settings). AppKit (specifically `NSTableView` via `NSViewControllerRepresentable`) is used for the high-performance file browsing components to ensure native macOS responsiveness, reliable selection, and interaction parity with Finder. 
Data is managed through `ObservableObject` ViewModels that interface with underlying singleton Services.

## Implemented Features
- **Device Management:** Auto-detects connected Android devices via ADB.
- **File Browsing:** High-performance, native-feeling file browser for Android and local Mac files.
- **Transfer Engine:** Robust push/pull operations supporting recursive directory copy, duplicates detection, and byte-level progress reporting.
- **Dual Pane & Backup:** Dedicated layouts for managing files side-by-side or performing targeted backups.
- **Clipboard:** Native copy/cut/paste across platforms (Android <-> Mac).

## Completed UI
- Modern macOS Sidebar
- Breadcrumb navigation
- Dual Pane mode with resizable splitter
- Native File Browser with sortable columns, custom icons, and proper mouse/keyboard interaction
- Progress Window with detailed metrics (ETA, Speeds, Progress)
- Native Status Bar with selection and size metrics

## Implemented Services
- **ADBManager:** Low-level bridge to execute ADB shell commands.
- **TransferService:** Core engine managing file transfer queues, progress polling, and executing actual adb push/pull.
- **ClipboardService:** Manages cross-platform clipboard state.
- **FileOperationService:** Handles file deletions, renaming, and duplication.
- **DatabaseManager:** SQLite backend for caching file metadata and backup records.
- **DirectoryCache:** In-memory caching for faster directory loads.

## Known Bugs
- N/A (Stabilized as of Beta-1).

## Known Limitations
- Progress updates for Mac to Android transfers rely on interpolation due to limitations in `adb push` stdout buffering.
- Moving files between two different Android devices natively is not implemented; it must be copied to Mac first.

## Future Roadmap
- Drag & Drop support between Android and Mac panes.
- File preview / QuickLook integration.
- Advanced conflict resolution UI for existing files.

## Files modified in this milestone
All source files within `Sources/` and the UI structural files have been stabilized. No further major architectural changes are planned.
