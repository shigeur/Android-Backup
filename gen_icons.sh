#!/bin/bash
SOURCE="/Users/ekopr/.gemini/antigravity/brain/85fcc6dc-5b6f-4689-8103-5fcbeec639ea/.user_uploaded/media__1784283865096.jpg"
DEST_DIR="Assets.xcassets/AppIcon.appiconset"

mkdir -p "$DEST_DIR"

sips -s format png -z 16 16 "$SOURCE" --out "$DEST_DIR/icon_16x16@1x.png"
sips -s format png -z 32 32 "$SOURCE" --out "$DEST_DIR/icon_16x16@2x.png"
sips -s format png -z 32 32 "$SOURCE" --out "$DEST_DIR/icon_32x32@1x.png"
sips -s format png -z 64 64 "$SOURCE" --out "$DEST_DIR/icon_32x32@2x.png"
sips -s format png -z 128 128 "$SOURCE" --out "$DEST_DIR/icon_128x128@1x.png"
sips -s format png -z 256 256 "$SOURCE" --out "$DEST_DIR/icon_128x128@2x.png"
sips -s format png -z 256 256 "$SOURCE" --out "$DEST_DIR/icon_256x256@1x.png"
sips -s format png -z 512 512 "$SOURCE" --out "$DEST_DIR/icon_256x256@2x.png"
sips -s format png -z 512 512 "$SOURCE" --out "$DEST_DIR/icon_512x512@1x.png"
sips -s format png -z 1024 1024 "$SOURCE" --out "$DEST_DIR/icon_512x512@2x.png"

# For dark mode, let's just make a copy as we can't easily filter it reliably
cp "$DEST_DIR/icon_512x512@2x.png" "$DEST_DIR/icon_dark_1024x1024.png"
cp "$DEST_DIR/icon_512x512@2x.png" "$DEST_DIR/icon_tinted_1024x1024.png"
