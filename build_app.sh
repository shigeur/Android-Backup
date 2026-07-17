#!/bin/bash

# Exit on error
set -e

APP_NAME="AndroidBackup"
DISPLAY_NAME="Android Backup"
BUILD_DIR=".build/release"
APP_BUNDLE="Android Backup.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"

echo "Building Swift Package..."
swift build -c release

echo "Creating App Bundle Structure..."
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Copying Executable..."
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/AndroidBackup"

echo "Generating Icon..."
# iconutil requires .iconset folder structure with exact naming: icon_16x16.png, icon_16x16@2x.png, etc.
# Assets.xcassets/AppIcon.appiconset has exactly these. We can just copy it to an .iconset and compile.
cp -r Assets.xcassets/AppIcon.appiconset AppIcon.iconset
iconutil -c icns AppIcon.iconset
mv AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
rm -rf AppIcon.iconset

echo "Generating Info.plist..."
cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AndroidBackup</string>
    <key>CFBundleIdentifier</key>
    <string>com.ninos.androidbackup</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>Beta-1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Codesigning app bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "Done! The application bundle '${APP_BUNDLE}' has been created."
