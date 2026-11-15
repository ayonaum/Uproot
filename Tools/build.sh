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

# The build's own exit status decides. A pipe into grep would hide it, and an app left over
# from an earlier build would then be copied out as if it were this one.
mkdir -p build
LOG=build/xcodebuild.log
if ! xcodebuild -project Uproot.xcodeproj -scheme Uproot -configuration Release \
        -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData build > "$LOG" 2>&1; then
    grep -E "error:|BUILD FAILED" "$LOG" >&2 || tail -n 20 "$LOG" >&2
    echo "build failed; the full log is in $LOG" >&2
    exit 1
fi
grep "warning: " "$LOG" | grep -v appintentsmetadataprocessor || true

PRODUCT=build/DerivedData/Build/Products/Release/Uproot.app
[ -d "$PRODUCT" ] || { echo "build failed: $PRODUCT is missing" >&2; exit 1; }

rm -rf dist/Uproot.app
mkdir -p dist
cp -R "$PRODUCT" dist/Uproot.app

# Signing again replaces the signature Xcode made, hardened runtime included, so every
# codesign call below asks for the runtime itself. Without it any program could load its own
# code into Uproot and borrow its Full Disk Access.
if [ "${1:-}" != "--adhoc" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ { print $2; exit }')
    if [ -n "$IDENTITY" ]; then
        if codesign --force --options runtime --sign "$IDENTITY" --timestamp=none dist/Uproot.app; then
            echo "signed with certificate $IDENTITY"
        else
            echo "could not sign with $IDENTITY; keeping the ad-hoc signature" >&2
            codesign --force --options runtime --sign - dist/Uproot.app
        fi
    else
        echo "no development certificate in the keychain; the app is signed ad hoc"
    fi
fi

codesign --verify --strict dist/Uproot.app
codesign -dv dist/Uproot.app 2>&1 | grep -q "flags=.*runtime" \
    || { echo "dist/Uproot.app is signed without the hardened runtime" >&2; exit 1; }
echo "built dist/Uproot.app"
