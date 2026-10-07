#!/bin/bash
# Builds a universal (Apple silicon + Intel) Stage Clock.app and a zip next to it.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/"Stage Clock.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O -target "$arch-apple-macos13.0" StageClock.swift -o "build/StageClock-$arch"
done
lipo -create build/StageClock-arm64 build/StageClock-x86_64 -output "$APP/Contents/MacOS/StageClock"
rm build/StageClock-*
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
(cd build && ditto -c -k --keepParent "Stage Clock.app" StageClock.zip)
echo "built: $(pwd)/build/StageClock.zip"
