#!/bin/bash
# Build DisplayOff.app (macOS, needs Xcode command line tools).
set -e
cd "$(dirname "$0")"
APP=DisplayOff.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  clang -c -fobjc-arc -target $arch-apple-macos26.0 Sources/Bridge.m -o "bridge-$arch.o"
  swiftc -O -swift-version 5 -target $arch-apple-macos26.0 -import-objc-header Sources/Bridge.h \
    Sources/main.swift "bridge-$arch.o" -framework IOKit -framework Cocoa -o "build-$arch"
done
lipo -create build-arm64 build-x86_64 -output "$APP/Contents/MacOS/DisplayOff"
rm -f build-arm64 build-x86_64 bridge-*.o
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DisplayOff</string>
<key>CFBundleIdentifier</key><string>jp.maniax.display-off</string>
<key>CFBundleName</key><string>DisplayOff</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
P
codesign --force --sign - "$APP"
echo "Built $APP  (run: open $APP, or $APP/Contents/MacOS/DisplayOff --off)"
