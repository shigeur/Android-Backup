# Android Backup

Android Backup is an open-source macOS application designed to make transferring files between Android devices and macOS significantly faster, easier, and more reliable.

## The Problem
Android's standard MTP (Media Transfer Protocol) performs incredibly poorly when transferring large directories containing thousands of small files (like Camera photos, WhatsApp media, or Voice Notes). MTP transfers these files sequentially and struggles under the high overhead, often resulting in agonizingly slow speeds or complete failure.

## The Solution
Android Backup bypasses MTP entirely by leveraging the **Android Debug Bridge (ADB)**. This allows for dramatically faster, parallelized transfers and guarantees reliability while providing a native, beautiful macOS interface.

## Features
- **Native macOS Interface:** Built with SwiftUI and AppKit to feel right at home on your Mac.
- **ADB Accelerated Transfers:** Bypasses MTP for maximum speed and stability.
- **Dual Pane File Manager:** Easily move files between Android and macOS side-by-side.
- **Backup Mode:** A dedicated mode for managing automated directory backups.
- **Native Clipboard:** Full support for `Cmd+C`, `Cmd+X`, and `Cmd+V` cross-platform.
- **Duplicate Detection:** Smart handling of duplicate files during transfers.
- **Progress Tracking:** Real-time metrics including ETA, transfer speed, and byte-level progress.

## Screenshots

<img width="2530" height="1390" alt="Android Backup 1" src="https://github.com/user-attachments/assets/516102d9-436c-4d05-8fce-7a789b1d607b" />

<img width="441" height="353" alt="image" src="https://github.com/user-attachments/assets/fb7bd55c-a296-40cd-9b69-9ff2784e5c63" />


## Requirements
- macOS 12.0 or later
- Android device with **USB Debugging** enabled
- Android Platform Tools (ADB)

## Installation & Build Instructions

1. Clone the repository:
```bash
git clone https://github.com/shigeur/Android-Backup.git
cd Android-Backup
```
2. Build the application using the included script:
```bash
./build_app.sh
```
3. Run the application:
```bash
open "Android Backup.app"
```

## Setup (ADB)
The application requires ADB to communicate with your device. If you have Android Studio installed, or `android-platform-tools` installed via Homebrew (`brew install android-platform-tools`), the app will auto-detect it. Otherwise, you can specify the manual path to the `adb` executable in the application's Settings.

## Roadmap
See [ROADMAP.md](ROADMAP.md) for planned features and future development goals.

## Credits
Designed and developed by Ninos.
Development assisted by Google Antigravity AI.

## License
This project is released under the [MIT License](LICENSE).
