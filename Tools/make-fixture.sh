#!/bin/sh
# Builds a small fake Mac in a folder, for trying Uproot without touching the real disk:
#
#   Tools/make-fixture.sh /tmp/uproot-playground
#   open Uproot.app --args --fixture /tmp/uproot-playground --name Terrain --name "Terrain FX" --vendor "Waves Crate" --scan
#
# The tree reproduces the clean-ups in "Terminal log.md": the Terrain plug-in with its
# vendor folders, and Safe Exam Browser inside a CrossOver bottle, along with the
# look-alikes that had to be filtered out by hand.

set -eu
[ $# -eq 1 ] || { echo "usage: $0 <empty folder>" >&2; exit 2; }
ROOT=$1
[ ! -e "$ROOT" ] || [ -z "$(ls -A "$ROOT" 2>/dev/null)" ] || { echo "$ROOT is not empty" >&2; exit 1; }

HOME_DIR="$ROOT/Users/tester"
mkdir -p "$ROOT/Applications" "$ROOT/Library" "$ROOT/Users/Shared" "$ROOT/usr/local/bin" "$ROOT/opt" \
         "$ROOT/private/etc" "$ROOT/private/var/db/receipts" "$ROOT/private/var/log" "$ROOT/private/var/tmp" \
         "$ROOT/private/tmp" "$ROOT/Volumes" "$HOME_DIR/Library"

# file <path> [kilobytes]
file() {
    mkdir -p "$(dirname "$1")"
    dd if=/dev/urandom of="$1" bs=1024 count="${2:-1}" 2>/dev/null
}

# bundle <path> <identifier> [kilobytes]
bundle() {
    name=$(basename "$1"); name=${name%.*}
    file "$1/Contents/MacOS/$name" "${3:-64}"
    cat > "$1/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
}

# --- Terrain and Terrain FX by Waves Crate ---
bundle "$ROOT/Applications/Terrain.app" com.wavescrate.terrain 4800
bundle "$ROOT/Applications/Terrain FX.app" com.wavescrate.terrainfx 3100
bundle "$ROOT/Library/Audio/Plug-Ins/VST3/Terrain.vst3" com.wavescrate.terrain.vst3 5200
bundle "$ROOT/Library/Audio/Plug-Ins/VST3/Terrain FX.vst3" com.wavescrate.terrainfx.vst3 3300
bundle "$ROOT/Library/Audio/Plug-Ins/Components/Terrain.component" com.wavescrate.terrain.au 5100
bundle "$ROOT/Library/Audio/Plug-Ins/Components/Terrain FX.component" com.wavescrate.terrainfx.au 3200
file "$ROOT/Library/Application Support/Waves Crate/Terrain/Content/wavetables.bin" 9000
file "$ROOT/Library/Application Support/Waves Crate/Terrain FX/Content/impulses.bin" 2400
file "$ROOT/Library/Logs/Terrain Crack Install.log" 3
file "$ROOT/Library/Logs/Terrain Designer Beta Install.log" 2
for preset in "5AM" "Human Nature" "Matriarch" "Gladiator V2" "Frog Face"; do
    file "$HOME_DIR/Library/WavesCrate/Terrain/Banks/Macshooter/$preset.terrain" 40
done
file "$HOME_DIR/Library/WavesCrate/Terrain/LicenceClock.txt"
file "$HOME_DIR/Library/WavesCrate/Terrain FX/InstrumentSettings.json" 2
file "$HOME_DIR/Library/Caches/Terrain/cache.db" 900
file "$HOME_DIR/Library/Caches/Terrain FX/cache.db" 400
file "$HOME_DIR/Library/Preferences/com.wavescrate.terrain.plist" 2
file "$HOME_DIR/Library/Saved Application State/com.wavescrate.terrain.savedState/windows.plist" 4
file "$HOME_DIR/Documents/Image-Line/FL Studio/Presets/Plugin database/Generators/Terrain.fst" 6
file "$HOME_DIR/Documents/Image-Line/FL Studio/Presets/Plugin database/Effects/Terrain FX.fst" 6
file "$HOME_DIR/Documents/Image-Line/FL Studio/Presets/Plugin database/Installed/Generators/New/Terrain.nfo" 1
file "$HOME_DIR/Documents/Image-Line/FL Studio/Presets/Plugin database/Installed/Effects/New/Terrain FX.nfo" 1
file "$HOME_DIR/Downloads/Telegram Desktop/Wavescrate - Terrain v1.0.0 [Mac]/Terrain Installer.pkg" 8000
for package in terrain.app terrain.vst3 terrain.au terrain.content terrainfx.app terrainfx.vst3 terrainfx.au terrain.crack; do
    cat > "$ROOT/private/var/db/receipts/com.wavescrate.$package.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>PackageIdentifier</key><string>com.wavescrate.$package</string>
<key>PackageVersion</key><string>1.0.0</string>
<key>InstallPrefixPath</key><string>/</string>
</dict></plist>
EOF
done

# Look-alikes that belong to other things.
file "$HOME_DIR/Library/Noizefield/Terrain/preset.fxp" 30
file "$HOME_DIR/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/data/base/graphics/terrain/grass.png" 200
file "$HOME_DIR/Library/Application Support/Steam/steamapps/common/SomeGame/data/terrain/tile.png" 300
file "$HOME_DIR/Library/Application Support/Steam/steamapps/common/SomeGame/data/terrain_textures/rock.png" 300
file "$HOME_DIR/Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps/common/RimWorld/Data/Core/Defs/TerrainDefs/Terrain_Road.xml" 4
file "$ROOT/Applications/FL Studio 2025.app/Contents/Resources/FL/Plugins/Fruity/Effects/ZGameEditor Visualizer/Effects/Terrain/Terrain Lattice.zgeproj" 20
file "$HOME_DIR/Documents/school/terrain analysis.docx" 80

# --- Safe Exam Browser in a CrossOver bottle ---
BOTTLE="$HOME_DIR/Library/Application Support/CrossOver/Bottles/Steam"
for library in Core WindowsApi I18n Logging Settings; do
    file "$BOTTLE/drive_c/Program Files/SafeExamBrowser/Application/SafeExamBrowser.$library.dll" 700
done
file "$BOTTLE/drive_c/Program Files/SafeExamBrowser/Application/seb_x64.dll" 2000
file "$BOTTLE/drive_c/users/crossover/AppData/Local/SafeExamBrowser/Logs/runtime.log" 12
file "$BOTTLE/drive_c/users/crossover/AppData/Roaming/SafeExamBrowser/settings.seb" 3
file "$BOTTLE/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Safe Exam Browser.lnk" 1
file "$BOTTLE/drive_c/users/crossover/AppData/Local/Temp/Safe_Exam_Browser_2026-10-20.log" 5
file "$BOTTLE/desktopdata/cxmenu/Shortcuts/CrossOver-363A1668-8BEE.safeexambrowser" 1
file "$HOME_DIR/Applications/CrossOver/SafeExamBrowser/Safe Exam Browser.app/Contents/Info.plist" 1
file "$HOME_DIR/Library/Preferences/org.safeexambrowser.SafeExamBrowser.plist" 2
file "$HOME_DIR/Downloads/SafeExamBrowser-3.7.1.1.dmg" 6000
file "$HOME_DIR/Downloads/config.seb" 2
bundle "$ROOT/Volumes/SafeExamBrowser-3.7.1.1/Safe Exam Browser.app" org.safeexambrowser.SafeExamBrowser 500

file "$ROOT/Applications/Waves/Data/Presets/CLA Epic/Artists/Sebastian Furrer/Lead Vox.xps" 2
file "$ROOT/Library/Arturia/Shared/images/designers/Hugo Sebastian.jpg" 30
file "$ROOT/Library/Arturia/Shared/images/designers/Seb Rochard.jpg" 30
file "$ROOT/Library/Arturia/Samples/Rev SPRING-636/Kicks/TkSEb_SG_IRGibbsLastTank_1908.rev" 60

echo "Fixture ready: $ROOT"
