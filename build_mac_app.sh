#!/bin/bash
set -euo pipefail

APP_NAME="SRT to FCPXML"
APP_DIR="$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
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
