#!/bin/sh
# Builds build/Notepad.app (universal, ad-hoc signed). Run on macOS with Xcode command line tools.
set -e
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
APP=build/Notepad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/Notepad" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
# empty .lproj folders make AppKit show its own panels (Save, Print, Fonts) in Korean too
for lang in en ko; do
    mkdir -p "$APP/Contents/Resources/$lang.lproj"
    touch "$APP/Contents/Resources/$lang.lproj/Localizable.strings"
done
codesign --force --sign - "$APP"
echo "Built $APP"
