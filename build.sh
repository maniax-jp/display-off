#!/bin/bash
# Build DisplayOff.app (macOS, needs Xcode command line tools).
set -e
cd "$(dirname "$0")"
APP=DisplayOff.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O Sources/main.swift -o "$APP/Contents/MacOS/DisplayOff"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DisplayOff</string>
<key>CFBundleIdentifier</key><string>jp.maniax.display-off</string>
<key>CFBundleName</key><string>DisplayOff</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign - "$APP"
echo "Built $APP  (run: open $APP, or $APP/Contents/MacOS/DisplayOff --off)"
