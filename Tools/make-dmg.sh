#!/bin/sh
# Packs the app into a disk image to hand to someone else:
#
#   Tools/make-dmg.sh        builds dist/Uproot.app and dist/Uproot-<version>.dmg
#
# The image holds the app, a shortcut to Applications to drag it onto, and install notes.
#
# The app in the image is always signed ad hoc. A development certificate carries no
# trust on another Mac and would only put its owner's name into a file that gets passed
# around. Without a paid Developer ID and notarization, the recipient has to approve the
# first launch by hand; the notes in the image say how.

set -eu
cd "$(dirname "$0")/.."

Tools/build.sh --adhoc

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/Uproot.app/Contents/Info.plist)
IMAGE="dist/Uproot-$VERSION.dmg"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R dist/Uproot.app "$STAGING/Uproot.app"
ln -s /Applications "$STAGING/Applications"
cp Tools/install-notes.txt "$STAGING/Как установить.txt"

rm -f "$IMAGE"
hdiutil create -quiet -volname "Uproot" -srcfolder "$STAGING" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$IMAGE"
echo "built $IMAGE ($(du -h "$IMAGE" | cut -f1 | tr -d ' '))"
