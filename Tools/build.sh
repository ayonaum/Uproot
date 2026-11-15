#!/bin/sh
# Builds the release app into dist/Uproot.app.
#
#   Tools/build.sh            build, and sign with a development certificate if the keychain has one
#   Tools/build.sh --adhoc    build with an ad-hoc signature only
#
# Why the signature matters: macOS ties Full Disk Access to who signed the app. With a
# certificate the permission survives rebuilds; with an ad-hoc signature every new build
# is a stranger and has to be switched on again in System Settings.

set -eu
cd "$(dirname "$0")/.."

xcodebuild -project Uproot.xcodeproj -scheme Uproot -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build \
    | grep -E "error|warning: |BUILD (SUCCEEDED|FAILED)" | grep -v appintentsmetadataprocessor || true

PRODUCT=build/DerivedData/Build/Products/Release/Uproot.app
[ -d "$PRODUCT" ] || { echo "build failed: $PRODUCT is missing" >&2; exit 1; }

rm -rf dist/Uproot.app
mkdir -p dist
cp -R "$PRODUCT" dist/Uproot.app

if [ "${1:-}" != "--adhoc" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ { print $2; exit }')
    if [ -n "$IDENTITY" ]; then
        if codesign --force --sign "$IDENTITY" --timestamp=none dist/Uproot.app; then
            echo "signed with certificate $IDENTITY"
        else
            echo "could not sign with $IDENTITY; keeping the ad-hoc signature" >&2
            codesign --force --sign - dist/Uproot.app
        fi
    else
        echo "no development certificate in the keychain; the app is signed ad hoc"
    fi
fi

codesign --verify --strict dist/Uproot.app
echo "built dist/Uproot.app"
