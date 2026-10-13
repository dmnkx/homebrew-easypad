#!/bin/sh
# Releases a version: sets it in Info.plist and the cask, builds, pushes, and uploads the zip to GitHub Releases.
# Usage: sh scripts/release.sh 1.2
set -e
cd "$(dirname "$0")/.."
V=$1
[ -n "$V" ] || { echo "usage: sh scripts/release.sh <version>"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first"; exit 1; }
sed -i '' "s|<key>CFBundleShortVersionString</key><string>[^<]*|<key>CFBundleShortVersionString</key><string>$V|" Info.plist
swift test
sh scripts/bundle.sh
rm -f build/EasyPad.zip
ditto -c -k --keepParent build/EasyPad.app build/EasyPad.zip
SHA=$(shasum -a 256 build/EasyPad.zip | cut -d' ' -f1)
sed -i '' -e "s/^  version \".*\"/  version \"$V\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/easypad.rb
git commit -qam "Release $V"
git push -q origin main
gh release create "v$V" build/EasyPad.zip --title "EasyPad $V" --generate-notes \
    --notes 'Install or update with Homebrew: `brew install dmnkx/easypad/easypad`'
echo "Released $V"
