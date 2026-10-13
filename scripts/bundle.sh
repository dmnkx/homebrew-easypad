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
# AppIcon.png becomes an .icns holding every size macOS asks for
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
