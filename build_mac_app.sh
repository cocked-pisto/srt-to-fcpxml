#!/bin/bash
set -euo pipefail

APP_NAME="SRT to FCPXML"
APP_DIR="$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
ICON_SOURCE="MacApp/Assets/AppIcon-1024.png"
ICONSET="/tmp/srt-fcpxml-AppIcon.iconset"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
tiffutil -cat \
  "$ICONSET/icon_16x16.png" \
  "$ICONSET/icon_32x32.png" \
  "$ICONSET/icon_128x128.png" \
  "$ICONSET/icon_256x256.png" \
  "$ICONSET/icon_512x512.png" \
  "$ICONSET/icon_512x512@2x.png" \
  -out /tmp/srt-fcpxml-AppIcon.tiff >/dev/null
tiff2icns /tmp/srt-fcpxml-AppIcon.tiff "$CONTENTS/Resources/AppIcon.icns"
xcrun swiftc \
  -parse-as-library \
  -O \
  -module-cache-path /tmp/srt-fcpxml-swift-module-cache \
  -framework SwiftUI \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  MacApp/SRTtoFCPXMLApp.swift \
  -o "$CONTENTS/MacOS/SRTtoFCPXML"

cp MacApp/Info.plist "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
echo "완료: $APP_DIR"
